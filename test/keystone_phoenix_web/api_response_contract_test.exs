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
end
