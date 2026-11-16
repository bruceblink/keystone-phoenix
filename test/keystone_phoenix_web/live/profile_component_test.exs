defmodule KeystonePhoenixWeb.ProfileComponentTest do
  @moduledoc "个人资料组件测试，验证首次读取失败与旧资料展示状态。"

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KeystonePhoenixWeb.Live.AdminPages.Accounts

  test "an initial read failure keeps the retry control and hides both forms" do
    html = render_component(&Accounts.profile/1, profile_assigns(false))

    assert html =~ "个人资料暂不可用，请重试"
    assert html =~ ~s(phx-value-panel="profile")
    refute html =~ ~s(phx-submit="save-profile")
    refute html =~ ~s(phx-submit="change-profile-password")
  end

  test "loaded profile data remains visible when a refresh fails" do
    html = render_component(&Accounts.profile/1, profile_assigns(true))

    assert html =~ "个人资料暂不可用，请重试"
    assert html =~ ~s(value="previous-name")
    assert html =~ ~s(phx-submit="save-profile")
    assert html =~ ~s(phx-submit="change-profile-password")
  end

  test "profile form remains visible for callers that omit the loaded state" do
    html =
      render_component(&Accounts.profile/1, Map.delete(profile_assigns(true), :profile_loaded))

    assert html =~ ~s(phx-submit="save-profile")
    assert html =~ ~s(phx-submit="change-profile-password")
  end

  defp profile_assigns(profile_loaded) do
    %{
      profile_loaded: profile_loaded,
      profile_form: %{
        "username" => "operator",
        "nickname" => "previous-name",
        "email" => "operator@example.com",
        "phoneNumber" => "",
        "avatar" => "",
        "sex" => nil
      },
      password_form: %{},
      profile_feedback: {:error, "service_unavailable", "个人资料暂不可用，请重试"}
    }
  end
end
