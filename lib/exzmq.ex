## This Source Code Form is subject to the terms of the Mozilla Public
## License, v. 2.0. If a copy of the MPL was not distributed with this
## file, You can obtain one at http://mozilla.org/MPL/2.0/.

defmodule Exzmq do
  use GenServer
  alias Exzmq.Address
  alias Exzmq.Socket
  require Logger

  @doc ~S"""
  Create a new CLIENT socket

  ## Example

  {:ok, socket} = Exzmq.client
  """
  def client do
    GenServer.start_link(__MODULE__, %Socket{type: :client})
  end

  def client(address) do
    with {:ok, socket} <- client(),
         :ok <- connect(socket, address) do
      {:ok, socket}
    end
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
    with {:ok, socket} <- server(),
         :ok <- bind(socket, address) do
      {:ok, socket}
    end
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
  def bind(socket, address) do
    GenServer.call(socket, {:bind, Address.parse(address)})
  end

  @doc ~S"""
  Connect a CLIENT socket

  ## Example

  {:ok, socket} = Exzmq.client
  Exzmq.connect(socket, "tcp://127.0.0.1:5555")
  """
  def connect(socket, address) do
    GenServer.call(socket, {:connect, Address.parse(address)})
  end

  @doc ~S"""
  Close ZeroMQ socket

  ## Example

  Exzmq.close(socket)
  """
  def close(socket) do
    GenServer.call(socket, :close)
  end

  def send(socket, message) do
    GenServer.call(socket, {:send, message})
  end

  def recv(socket) do
    GenServer.call(socket, :recv)
  end

  # private functions

  def handle_call(:accept, _from, state) do
    {:ok, _} = :gen_tcp.accept(state.socket)

    {:noreply, state}
  end

  def handle_call({:bind, address}, _from, state) do
    opts = [:inet, :binary, active: :once, ip: address.ip, reuseaddr: true]

    with {:ok, socket} <- :gen_tcp.listen(address.port, opts),
         acceptor_state <- %{parent: self(), socket: socket},
         {:ok, acceptor} <- GenServer.start_link(Exzmq.Acceptor, acceptor_state),
         :ok <- :gen_tcp.controlling_process(socket, acceptor) do
      {:reply, :ok, %{state | acceptor: acceptor, address: address, socket: socket}}
    else
      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:connect, address}, _from, state) do
    opts = [:inet, :binary, active: :once]

    with {:ok, socket} <- :gen_tcp.connect(address.ip, address.port, opts),
         :ok <- :gen_tcp.send(socket, <<0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0x7F, 0x03>>) do
      :inet.setopts(socket, [{:active, :once}])

      {:reply, :ok, %{state | address: address, socket: socket}}
    else
      error ->
        {:reply, error, state}
    end
  end

  def handle_call(:close, _from, state) do
    {:reply, :gen_tcp.close(state.socket), state}
  end

  def handle_call({:send, message}, _from, state) do
    encoded_message = Exzmq.Frame.encode(message)
    reply = :gen_tcp.send(state.socket, encoded_message)

    {:reply, reply, state}
  end

  def handle_call(:recv, _from, %{messages: messages} = state) do
    if Enum.empty?(messages) do
      {:reply, nil, %{state | messages: List.delete_at(messages, 0)}}
    else
      {:reply, List.first(messages), %{state | messages: List.delete_at(messages, 0)}}
    end
  end

  def handle_call({:new_client, client}, _from, state) do
    conn = %Exzmq.ClientConnection{socket: client}
    state = %{state | clients: [conn] ++ state.clients}
    :gen_tcp.send(client, <<0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0x7F, 0x03>>)
    :inet.setopts(client, [{:active, :once}])

    {:noreply, state}
  end

  def handle_call(_message, _from, state) do
    {:noreply, state}
  end

  def handle_info(
        {:tcp, socket, <<0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0x7F, 0x03>>},
        %Exzmq.Socket{type: :client, state: :greeting} = state
      ) do
    :ok = :gen_tcp.send(socket, <<0x01, "NULL", 0x00, 0::size(248)>>)
    :inet.setopts(socket, [{:active, :once}])

    Logger.info("ZeroMQ (client) state: greeting -> greeting2")

    {:noreply, %{state | state: :greeting2}}
  end

  def handle_info(
        {:tcp, socket, <<0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0x7F, 0x03>>},
        %Exzmq.Socket{type: :server, state: :greeting} = state
      ) do
    :ok = :gen_tcp.send(socket, <<0x01, "NULL", 0x00, 0::size(248)>>)
    :inet.setopts(socket, [{:active, :once}])

    Logger.info("ZeroMQ (server) state: greeting -> greeting2")

    {:noreply, %{state | state: :greeting2}}
  end

  @client_ready_command Exzmq.Command.encode_ready("CLIENT")
  @server_ready_command Exzmq.Command.encode_ready("SERVER")

  # CLIENT SEND READY
  def handle_info(
        {:tcp, socket, <<0x01, "NULL", 0x00, 0::size(248)>>},
        %Exzmq.Socket{type: :client, state: :greeting2} = state
      ) do
    :ok = :gen_tcp.send(socket, @client_ready_command)
    :inet.setopts(socket, [{:active, :once}])

    Logger.info("ZeroMQ (client) state: greeting2 -> handshake")

    {:noreply, %{state | state: :handshake}}
  end

  # SERVER GOT READY
  def handle_info(
        {:tcp, socket, @client_ready_command},
        %Exzmq.Socket{type: :server, state: :handshake} = state
      ) do
    :ok = :gen_tcp.send(socket, @server_ready_command)
    :inet.setopts(socket, [{:active, :once}])

    Logger.info("ZeroMQ (server) state: handshake -> messages")

    {:noreply, %{state | state: :messages}}
  end

  # CLIENT GOT READY
  def handle_info(
        {:tcp, socket, @server_ready_command},
        %Exzmq.Socket{type: :client, state: :handshake} = state
      ) do
    :inet.setopts(socket, [{:active, :once}])

    Logger.info("ZeroMQ (client) state: handshake -> messages")

    {:noreply, %{state | state: :messages}}
  end

  # SERVER GOT HANDSHAKE
  def handle_info(
        {:tcp, socket, <<0x01, "NULL", 0x00, 0::size(248)>>},
        %Exzmq.Socket{type: :server, state: :greeting2} = state
      ) do
    :inet.setopts(socket, [{:active, :once}])

    Logger.info("ZeroMQ (client) state: greeting2 -> handshake")

    {:noreply, %{state | state: :handshake}}
  end

  ## SERVER GOT MESSAGE
  def handle_info(
        {:tcp, _socket, message},
        %Exzmq.Socket{type: :server, state: :messages} = state
      ) do
    decoded = Exzmq.Frame.decode(message)
    messages = state.messages ++ [decoded]

    Logger.info("ZeroMQ (server) received message: #{inspect(decoded)}")

    {:noreply, %{state | state: :messages, messages: messages}}
  end

  def handle_info({:tcp_closed, socket}, %Exzmq.Socket{type: :server} = state) do
    clients = Enum.filter(state.clients, fn x -> x != socket end)

    Logger.info("ZeroMQ (server) client disconnected: #{inspect(socket)}")

    {:noreply, %{state | clients: clients}}
  end

  def handle_info(info, %Exzmq.Socket{type: type} = state) do
    Logger.warn("ZeroMQ (#{type}) unhandled event: #{inspect(info)}")

    {:noreply, state}
  end
end
