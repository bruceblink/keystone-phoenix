defmodule KeystonePhoenix.Auth.CaptchaTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenix.Auth.Captcha

  test "renders the frontend-compatible GIF dimensions" do
    gif = Captcha.render_gif("2+3=")

    assert <<"GIF89a", width::little-16, height::little-16, _rest::binary>> = gif
    assert width == 160
    assert height == 60
    assert byte_size(gif) > 100
  end
end
