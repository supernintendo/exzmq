## This Source Code Form is subject to the terms of the Mozilla Public
## License, v. 2.0. If a copy of the MPL was not distributed with this
## file, You can obtain one at http://mozilla.org/MPL/2.0/.

defmodule ClientConnectTest do
  use ExUnit.Case, async: false

  test "Client should fail to connect" do
    {:ok, client} = Exzmq.client()
    {:error, :econnrefused} = Exzmq.connect(client, "tcp://127.0.0.1:5555")
  end

  test "Client should connect" do
    {:ok, server} = Exzmq.server()
    :ok = Exzmq.bind(server, "tcp://127.0.0.1:5555")
    :timer.sleep(2000)

    {:ok, client} = Exzmq.client()
    :ok = Exzmq.connect(client, "tcp://127.0.0.1:5555")
    :timer.sleep(2000)

    :ok = Exzmq.send(client, "Hello")
    :timer.sleep(1000)
    msg = Exzmq.recv(server)

    assert msg == "Hello"
    :ok = Exzmq.close(client)
    :ok = Exzmq.close(server)
  end
end
