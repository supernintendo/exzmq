## This Source Code Form is subject to the terms of the Mozilla Public
## License, v. 2.0. If a copy of the MPL was not distributed with this
## file, You can obtain one at http://mozilla.org/MPL/2.0/.

defmodule Exzmq.Acceptor do
  @moduledoc """
  This GenServer waits for incoming connections.
  Once a new connection is accepted, it is passed over to the parent SERVER socket.
  """

  use GenServer

  def init(state) do
    GenServer.cast(self(), :accept)

    {:ok, state}
  end

  def handle_cast(:accept, state) do
    with {:ok, client} <- :gen_tcp.accept(state.socket),
         :ok <- :gen_tcp.controlling_process(client, state.parent) do
      GenServer.call(state.parent, {:new_client, client})
    end

    GenServer.cast(self(), :accept)

    {:noreply, state}
  end
end
