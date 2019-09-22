## This Source Code Form is subject to the terms of the Mozilla Public
## License, v. 2.0. If a copy of the MPL was not distributed with this
## file, You can obtain one at http://mozilla.org/MPL/2.0/.

defmodule Exzmq.Frame do
  def decode(<<0x00, _len::size(8), payload::binary>>) do
    payload
  end

  def encode(msg) when is_binary(msg) do
    case byte_size(msg) do
      msg_length when msg_length > 255 ->
        [<<0x02, msg_length::size(64)>>, msg]

      msg_length ->
        [<<0x00, msg_length::size(8)>>, msg]
    end
    |> IO.iodata_to_binary()
  end
end
