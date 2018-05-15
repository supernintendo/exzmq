## This Source Code Form is subject to the terms of the Mozilla Public
## License, v. 2.0. If a copy of the MPL was not distributed with this
## file, You can obtain one at http://mozilla.org/MPL/2.0/.

defmodule Exzmq do

  use GenServer

  alias Exzmq.Address
  alias Exzmq.Socket

  @doc ~S"""
  Create a new CLIENT socket

  ## Example

  {:ok, socket} = Exzmq.client
  """
  def client do
    GenServer.start_link(__MODULE__, %Socket{type: :client})
  end
  def client(address) do
    {:ok, socket} = client()
    :ok = socket |> connect(address)
    {:ok, socket}
  end


  @doc ~S"""
  Create a new SERVER socket

  ## Examples

  {:ok, socket} = Exzmq.server
  """
  def server do
    GenServer.start_link(__MODULE__, %Socket{type: :server})
  end
  def server(address) do
    {:ok, socket} = server()
    :ok = socket |> bind(address)
    {:ok, socket}
  end

  def init(state) do
    {:ok, state}
  end


  @doc ~S"""
  Accept connections on a SERVER socket

  ## Example

  {:ok, server} = Exzmq.server
  Exzmq.bind(server, "tcp://127.0.0.1:5555")
  """
  def bind(socket, address)  do
    socket |> GenServer.call({:bind, address |> Address.parse})
  end


  @doc ~S"""
  Connect a CLIENT socket

  ## Example

  {:ok, socket} = Exzmq.client
  Exzmq.connect(socket, "tcp://127.0.0.1:5555")
  """
  def connect(socket, address) do
    socket |> GenServer.call({:connect, address |> Address.parse})
  end


  @doc ~S"""
  Close ZeroMQ socket

  ## Example

  Exzmq.close(socket)
  """
  def close(socket) do
    socket |> GenServer.call(:close)
  end


  def send(socket, message) do
    socket |> GenServer.call({:send, message})
  end

  def recv(socket) do
    x = socket |> GenServer.call(:recv)
    x
  end


  # private functions

  def handle_call(:accept, _from, state) do
    {:ok, _} = :gen_tcp.accept(state.socket)

    {:noreply, state}
  end

  def handle_call({:bind, address}, _from, state) do
    opts = [:inet, :binary, active: :once, ip: address.ip, reuseaddr: true]
    case :gen_tcp.listen(address.port, opts) do
      {:ok, socket} ->
        acceptor_state = %{parent: self(), socket: socket}
        {:ok, acceptor} = GenServer.start_link(Exzmq.Acceptor, acceptor_state)
        :ok = :gen_tcp.controlling_process(socket, acceptor)
        state = %{state | acceptor: acceptor}
        {:reply, :ok, %{state | address: address, socket: socket}}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:connect, address}, _from, state) do
    opts = [:inet, :binary, active: :once]
    case :gen_tcp.connect(address.ip, address.port, opts) do
      {:ok, socket} ->
        case :gen_tcp.send(socket, <<0xff, 0, 0, 0, 0, 0, 0, 0, 0, 0x7f, 0x03>>) do
          :ok ->
            :inet.setopts(socket, [{:active, :once}])
            {:reply, :ok, %{state | address: address, socket: socket}}
          error -> {:reply, error, state}
        end
      error -> {:reply, error, state}
    end
  end

  def handle_call(:close, _from, state) do
    {:reply, :gen_tcp.close(state.socket), state}
  end

  def handle_call({:send, message}, _from, state) do
    reply = state.socket |> :gen_tcp.send(Exzmq.Frame.encode(message))
    {:reply, reply, state}
  end

  def handle_call(:recv, _from, state) do
    msg = cond do
      state.messages |> Enum.empty? ->
        "NO MESSAGE"
      true ->
        state.messages |> List.first
    end
    state = %{state | messages: state.messages |> List.delete_at(0)}

    {:reply, msg, state}
  end

  def handle_call(message, _from, state) do
    {:noreply, state}
  end

  def handle_cast({:new_client, client}, state) do
    conn = %Exzmq.ClientConnection{socket: client}
    state = %{state | clients: [conn] ++ state.clients}
    :gen_tcp.send(client, <<0xff, 0, 0, 0, 0, 0, 0, 0, 0, 0x7f, 0x03>>)
    :inet.setopts(client, [{:active, :once}])

    {:noreply, state}
  end

  def handle_cast(message, _from, state) do
    {:ok, state}
  end

  def handle_info({:tcp, socket, <<0xff, 0, 0, 0, 0, 0, 0, 0, 0, 0x7f, 0x03>>}, %Exzmq.Socket{type: :client, state: :greeting} = state) do
    :ok = :gen_tcp.send(socket, <<0x01, "NULL", 0x00, 0::size(248)>>)
    :inet.setopts(socket, [{:active, :once}])

    {:noreply, %{state | state: :greeting2}}
  end

  def handle_info({:tcp, socket, <<0xff, 0, 0, 0, 0, 0, 0, 0, 0, 0x7f, 0x03>>}, %Exzmq.Socket{type: :server, state: :greeting} = state) do
    :ok = :gen_tcp.send(socket, <<0x01, "NULL", 0x00, 0::size(248)>>)
    :inet.setopts(socket, [{:active, :once}])

    {:noreply, %{state | state: :greeting2}}
  end

  @client_ready Exzmq.Command.encode_ready("CLIENT")
  @server_ready Exzmq.Command.encode_ready("SERVER")

  # CLIENT SEND READY
  def handle_info({:tcp, socket, <<0x01, "NULL", 0x00, 0::size(248)>>}, %Exzmq.Socket{type: :client, state: :greeting2} = state) do
    :ok = :gen_tcp.send(socket, @client_ready)
    :inet.setopts(socket, [{:active, :once}])

    {:noreply, %{state | state: :handshake}}
  end

  # SERVER GOT READY
  def handle_info({:tcp, socket, @client_ready}, %Exzmq.Socket{type: :server, state: :handshake} = state) do
    :ok = :gen_tcp.send(socket, @server_ready)
    :inet.setopts(socket, [{:active, :once}])

    {:noreply, %{state | state: :messages}}
  end

  # CLIENT GOT READY
  def handle_info({:tcp, socket, @server_ready}, %Exzmq.Socket{type: :client, state: :handshake} = state) do
    :inet.setopts(socket, [{:active, :once}])

    {:noreply, %{state | state: :messages}}
  end

  # SERVER GOT HANDSHAKE
  def handle_info({:tcp, socket, <<0x01, "NULL", 0x00, 0::size(248)>>}, %Exzmq.Socket{type: :server, state: :greeting2} = state) do
    :inet.setopts(socket, [{:active, :once}])

    {:noreply, %{state | state: :handshake}}
  end

  ## SERVER GOT MESSAGE
  def handle_info({:tcp, _socket, message}, %Exzmq.Socket{type: :server, state: :messages} = state) do
    decoded = message |> Exzmq.Frame.decode
    {:noreply, %{state | state: :messages, messages: state.messages ++ [decoded]}}
  end

  def handle_info({:tcp_closed, socket}, %Exzmq.Socket{type: :server} = state) do
    clients = state.clients
    |> Enum.filter(fn(x) -> x != socket end)
    state = %{state | clients: clients}

    {:noreply, state}
  end

  def handle_info(info, state) do
    {:noreply, state}
  end
end
