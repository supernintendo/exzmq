## This Source Code Form is subject to the terms of the Mozilla Public
## License, v. 2.0. If a copy of the MPL was not distributed with this
## file, You can obtain one at http://mozilla.org/MPL/2.0/.

defmodule Exzmq.Address do
  # transport: currently, only :tcp is supported
  # ip: an IP address as Erlang tuple
  # port: the port number
  defstruct transport: :tcp, ip: nil, port: nil

  def parse(%Exzmq.Address{} = address), do: address

  def parse(address) do
    unless String.starts_with?(address, "tcp://") do
      raise "Unsupported transport: #{address}"
    end

    # Split IP and port from address string
    [ip, port] =
      address
      |> String.slice(6, 999)
      |> String.split(":")

    # Cast IP string to an ip4_address()
    {:ok, ip} =
      ip
      |> String.to_charlist()
      |> :inet.parse_address()

    %Exzmq.Address{ip: ip, port: String.to_integer(port)}
  end
end
