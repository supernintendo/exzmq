## This Source Code Form is subject to the terms of the Mozilla Public
## License, v. 2.0. If a copy of the MPL was not distributed with this
## file, You can obtain one at http://mozilla.org/MPL/2.0/.

defmodule Exzmq.Command do
  @moduledoc """
  This module contains helpers to encode/decode commands as per ZeroMQ spec.
  """

  def encode_ready(type, metadata \\ %{}) do
    metadata
    |> Map.put(:"Server-Type", type)
    |> encode_metadata()
    |> encode_command("READY")
    |> encode_packet()
  end

  def encode_metadata(metadata) do
    metadata
    |> Enum.map_reduce([], fn {key, value} = e, acc ->
      key_string = Atom.to_string(key)
      value_length = String.length(value)

      {e, acc ++ [String.length(key_string), key_string, <<value_length::size(32)>>, value]}
    end)
    |> elem(1)
    |> IO.iodata_to_binary()
  end

  def encode_command(encoded_metadata, command_name) do
    IO.iodata_to_binary([<<0xD5, "#{command_name}">>, encoded_metadata])
  end

  def encode_packet(encoded_command) do
    case byte_size(encoded_command) do
      command_size when command_size <= 255 ->
        [<<0x04, command_size::size(8)>>, encoded_command]

      command_size ->
        [<<0x06, command_size::size(64)>>, encoded_command]
    end
    |> IO.iodata_to_binary()
  end
end
