defmodule KeystonePhoenix.Auth.Captcha do
  @moduledoc """
  ETS-backed one-time login captchas.

  The original Keystone contract returns a raw Base64 image and the frontend
  supplies the `data:image/gif;base64,` prefix. The image is generated as a
  small indexed GIF here so the project does not need a native image library.
  """

  import Bitwise

  alias KeystonePhoenix.Config
  alias KeystonePhoenix.RuntimeStore

  @config_key "sys.account.captchaOnOff"
  @captcha_prefix "keystone:auth:captcha:"
  @captcha_ttl 120
  @width 160
  @height 60
  @scale 3
  @chars ~c"23456789"

  @glyphs %{
    "0" => ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1" => ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2" => ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3" => ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4" => ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5" => ["11111", "10000", "10000", "11110", "00001", "00001", "11110"],
    "6" => ["01110", "10000", "10000", "11110", "10001", "10001", "01110"],
    "7" => ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8" => ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9" => ["01110", "10001", "10001", "01111", "00001", "00001", "01110"],
    "+" => ["00000", "00100", "00100", "11111", "00100", "00100", "00000"],
    "-" => ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    "=" => ["00000", "11111", "00000", "11111", "00000", "00000", "00000"]
  }

  @doc "Returns whether the database-backed login captcha switch is enabled."
  def enabled? do
    Config.get_config_value_by_key(@config_key) == "true"
  end

  @doc "Creates a one-time captcha response compatible with Keystone's frontend."
  def generate do
    if enabled?() do
      {text, answer} = challenge()
      key = random_key()

      case store(key, answer) do
        :ok -> {:ok, %{captcha_code_key: key, captcha_code_img: Base.encode64(render_gif(text))}}
        {:error, :unavailable} = error -> error
      end
    else
      {:ok, %{captcha_code_key: nil, captcha_code_img: nil}}
    end
  end

  @doc "Consumes and validates a captcha key when the login switch is enabled."
  def validate(code, key) do
    cond do
      not enabled?() -> :ok
      blank?(code) or blank?(key) -> {:error, :captcha_required}
      true -> consume_and_compare(to_string(key), to_string(code))
    end
  end

  @doc false
  def render_gif(text) when is_binary(text) do
    dark_pixels =
      text
      |> draw_text()
      |> add_noise()

    pixels =
      for y <- 0..(@height - 1), x <- 0..(@width - 1) do
        if MapSet.member?(dark_pixels, {x, y}), do: 1, else: 0
      end

    gif(pixels)
  end

  defp challenge do
    case captcha_type() do
      "char" ->
        answer = Enum.map_join(1..5, fn _ -> random_char() end)
        {answer, answer}

      _ ->
        first = random_integer(1, 9)
        second = random_integer(1, 9)
        {"#{first}+#{second}=", Integer.to_string(first + second)}
    end
  end

  defp captcha_type do
    Application.get_env(:keystone_phoenix, :captcha_type, "math")
    |> to_string()
    |> String.downcase()
  end

  defp random_char do
    Enum.at(@chars, random_integer(0, length(@chars) - 1))
  end

  defp random_key, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

  defp random_integer(min, max) when min <= max do
    <<number::unsigned-integer-size(32)>> = :crypto.strong_rand_bytes(4)
    min + rem(number, max - min + 1)
  end

  defp store(key, answer) do
    :ets.insert(
      RuntimeStore.captcha_table(),
      {@captcha_prefix <> key, answer, expires_at()}
    )

    :ok
  rescue
    _error -> {:error, :unavailable}
  end

  defp consume_and_compare(key, code) do
    now = System.monotonic_time(:millisecond)

    case :ets.take(RuntimeStore.captcha_table(), @captcha_prefix <> key) do
      [] ->
        {:error, :captcha_expired}

      [{_key, answer, expires_at}] when expires_at > now ->
        if String.downcase(String.trim(answer)) == String.downcase(String.trim(code)),
          do: :ok,
          else: {:error, :captcha_invalid}

      _ ->
        {:error, :captcha_expired}
    end
  rescue
    _error -> {:error, :unavailable}
  end

  defp expires_at, do: System.monotonic_time(:millisecond) + @captcha_ttl * 1_000

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: true

  defp draw_text(text) do
    glyph_width = 5 * @scale
    spacing = @scale
    text_width = String.length(text) * glyph_width + max(String.length(text) - 1, 0) * spacing
    start_x = max(div(@width - text_width, 2), 0)
    start_y = div(@height - 7 * @scale, 2)

    text
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.reduce(MapSet.new(), fn {character, index}, pixels ->
      glyph = Map.get(@glyphs, character, @glyphs["0"])
      origin_x = start_x + index * (glyph_width + spacing)

      Enum.reduce(Enum.with_index(glyph), pixels, fn {row, y}, pixels ->
        Enum.reduce(Enum.with_index(String.graphemes(row)), pixels, fn {pixel, x}, pixels ->
          if pixel == "1" do
            draw_block(pixels, origin_x + x * @scale, start_y + y * @scale)
          else
            pixels
          end
        end)
      end)
    end)
  end

  defp draw_block(pixels, origin_x, origin_y) do
    for y <- origin_y..(origin_y + @scale - 1),
        x <- origin_x..(origin_x + @scale - 1),
        x >= 0,
        x < @width,
        y >= 0,
        y < @height,
        reduce: pixels do
      pixels -> MapSet.put(pixels, {x, y})
    end
  end

  defp add_noise(pixels) do
    Enum.reduce(1..36, pixels, fn _, pixels ->
      x = random_integer(0, @width - 1)
      y = random_integer(0, @height - 1)
      MapSet.put(pixels, {x, y})
    end)
  end

  defp gif(pixels) do
    image_data = lzw_image_data(pixels)

    [
      "GIF89a",
      <<@width::little-16, @height::little-16, 0xF0, 0, 0>>,
      <<255, 255, 255, 20, 30, 60>>,
      <<0x2C, 0, 0, 0, 0, @width::little-16, @height::little-16, 0>>,
      image_data,
      <<0x3B>>
    ]
    |> IO.iodata_to_binary()
  end

  defp lzw_image_data(pixels) do
    clear_code = 4
    end_code = 5

    codes =
      pixels
      |> Enum.flat_map(fn pixel -> [clear_code, pixel] end)
      |> Kernel.++([end_code])

    bytes =
      codes
      |> Enum.flat_map(fn code -> for bit <- 0..2, do: code >>> bit &&& 1 end)
      |> Enum.chunk_every(8)
      |> Enum.map(fn bits ->
        bits
        |> Enum.with_index()
        |> Enum.reduce(0, fn {bit, index}, byte -> byte ||| bit <<< index end)
      end)
      |> IO.iodata_to_binary()

    blocks =
      bytes
      |> :binary.bin_to_list()
      |> Enum.chunk_every(255)
      |> Enum.map(fn block -> [<<length(block)>>, block] end)

    [<<2>>, blocks, <<0>>]
  end
end
