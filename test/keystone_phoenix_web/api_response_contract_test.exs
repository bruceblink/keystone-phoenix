defmodule KeystonePhoenixWeb.ApiResponseContractTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenixWeb.ApiResponse

  test "success envelope always exposes the four contract fields" do
    assert ApiResponse.ok(%{id: "sample"}) == %{
             success: true,
             data: %{id: "sample"},
             message: "OK",
             error: nil
           }
  end

  test "error envelope exposes only a registered category" do
    response = ApiResponse.error(:permission_denied, "没有操作权限", %{resource: "user"})

    assert response == %{
             success: false,
             data: %{resource: "user"},
             message: "没有操作权限",
             error: %{code: "permission_denied"}
           }

    refute Map.has_key?(response, :code)
    refute Map.has_key?(response, :msg)
    assert Enum.all?(ApiResponse.error_codes(), &ApiResponse.valid_error_code?/1)
  end

  test "unknown categories fail before an invalid response is emitted" do
    assert_raise ArgumentError, ~r/unsupported API error code/, fn ->
      ApiResponse.error(:legacy_numeric_code, "invalid")
    end
  end

  test "catalog metadata makes every business code searchable" do
    assert %{status: 409, retryable: false, message_key: "auth.active_session_conflict"} =
             ApiResponse.error_metadata(:active_session_conflict)

    assert %{status: 429, retryable: true} = ApiResponse.error_metadata(:rate_limited)

    assert %{status: 422, retryable: false} = ApiResponse.error_metadata(:role_has_members)
    assert %{status: 422, retryable: false} = ApiResponse.error_metadata(:role_protected)

    assert %{status: 422, retryable: false, message_key: "error.username_already_exists"} =
             ApiResponse.error_metadata(:username_already_exists)

    assert %{status: 422, retryable: false, message_key: "error.username_invalid_format"} =
             ApiResponse.error_metadata(:username_invalid_format)

    assert %{status: 422, retryable: false, message_key: "error.password_same_as_current"} =
             ApiResponse.error_metadata(:password_same_as_current)

    for code <- ~w(
          password_required
          password_too_short
          password_disallowed
          password_contains_username
          password_missing_uppercase
          password_missing_lowercase
          password_missing_digit
          password_missing_special
        ) do
      metadata = ApiResponse.error_metadata(code)
      assert %{status: 422, retryable: false} = metadata
      assert metadata.message_key == "error." <> code
    end

    assert %{code: "password_same_as_current", status: 422} =
             ApiResponse.error_lookup("password_same_as_current")

    assert %{code: "active_session_conflict", status: 409} =
             ApiResponse.error_lookup(" active_session_conflict ")

    assert ApiResponse.error_lookup("unknown_code") == nil

    assert Enum.all?(
             ApiResponse.error_codes(),
             &(is_binary(&1) and ApiResponse.valid_error_code?(&1))
           )
  end
end
