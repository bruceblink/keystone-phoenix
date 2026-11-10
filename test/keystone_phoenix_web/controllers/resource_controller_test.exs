defmodule KeystonePhoenixWeb.ResourceControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

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
    assert json_response(response, 401)["code"] == 40101
  end
end
