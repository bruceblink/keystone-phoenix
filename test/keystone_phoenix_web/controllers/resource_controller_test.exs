defmodule KeystonePhoenixWeb.ResourceControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenixWeb.ResourceController

  @owner_id "018f2a7e-5d3c-7b01-8a11-000000000042"

  setup do
    directory =
      Path.join(System.tmp_dir!(), "keystone-resource-#{System.unique_integer([:positive])}")

    Application.put_env(:keystone_phoenix, :file_base_dir, directory)
    File.mkdir_p!(Path.join(directory, "avatar"))
    File.mkdir_p!(Path.join(directory, "download"))

    on_exit(fn ->
      Application.delete_env(:keystone_phoenix, :file_base_dir)
      File.rm_rf!(directory)
    end)

    {:ok, directory: directory}
  end

  test "only avatar resources are public", %{directory: directory, conn: conn} do
    File.write!(Path.join(directory, "avatar/public.png"), <<0x89, "PNG", 0x0D, 0x0A>>)
    File.write!(Path.join(directory, "download/private.txt"), "private")

    assert get(build_conn(), "/profile/avatar/public.png").status == 200

    response = get(conn, "/profile/download/private.txt")
    assert response.status == 401
    assert get_in(json_response(response, 401), ["error", "code"]) == "session_revoked"
  end

  test "generic profile resources are limited to their owner", %{directory: directory} do
    File.mkdir_p!(Path.join(directory, "upload/#{@owner_id}"))
    File.write!(Path.join(directory, "upload/#{@owner_id}/report.txt"), "private")

    owner_conn =
      Plug.Conn.assign(
        Plug.Test.conn(:get, "/profile/upload/#{@owner_id}/report.txt"),
        :current_user,
        %{user_id: @owner_id}
      )

    owner_response =
      ResourceController.show(owner_conn, %{"path" => ["upload", @owner_id, "report.txt"]})

    assert owner_response.status == 200
    assert owner_response.resp_body == "private"

    other_conn =
      Plug.Conn.assign(
        Plug.Test.conn(:get, "/profile/upload/#{@owner_id}/report.txt"),
        :current_user,
        %{user_id: "018f2a7e-5d3c-7b01-8a11-000000000043"}
      )

    other_response =
      ResourceController.show(other_conn, %{"path" => ["upload", @owner_id, "report.txt"]})

    assert other_response.status == 403

    legacy_conn = Plug.Test.conn(:get, "/profile/upload/report.txt")
    legacy_response = ResourceController.show(legacy_conn, %{"path" => ["upload", "report.txt"]})
    assert legacy_response.status == 404

    traversal_conn =
      Plug.Test.conn(:get, "/profile/upload/#{@owner_id}/../43/report.txt")
      |> Plug.Conn.assign(:current_user, %{user_id: @owner_id})

    traversal_response =
      ResourceController.show(traversal_conn, %{
        "path" => ["upload", @owner_id, "..", "43", "report.txt"]
      })

    assert traversal_response.status == 404
  end
end
