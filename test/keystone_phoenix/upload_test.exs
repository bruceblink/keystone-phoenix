defmodule KeystonePhoenix.UploadTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias KeystonePhoenix.Upload
  alias KeystonePhoenixWeb.ResourceController

  setup do
    directory =
      Path.join(System.tmp_dir!(), "keystone-upload-#{System.unique_integer([:positive])}")

    old_directory = Application.get_env(:keystone_phoenix, :file_base_dir)
    Application.put_env(:keystone_phoenix, :file_base_dir, directory)

    on_exit(fn ->
      if old_directory do
        Application.put_env(:keystone_phoenix, :file_base_dir, old_directory)
      else
        Application.delete_env(:keystone_phoenix, :file_base_dir)
      end

      File.rm_rf!(directory)
    end)

    :ok
  end

  test "rejects non-image uploads before storing them" do
    path = temporary_file("avatar.html", "<script>alert(1)</script>")
    upload = %Plug.Upload{path: path, filename: "avatar.html", content_type: "text/html"}

    assert {:error, :type_not_allowed} = Upload.store_avatar(upload)
    File.rm!(path)
  end

  test "accepts a valid PNG signature" do
    png = <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0>>
    path = temporary_file("avatar.png", png)
    upload = %Plug.Upload{path: path, filename: "avatar.png", content_type: "image/png"}

    assert {:ok, "/profile/avatar/" <> _filename} = Upload.store_avatar(upload)
    File.rm!(path)
  end

  test "stores generic files and rejects unsafe download paths" do
    path = temporary_file("report.txt", "hello")
    upload = %Plug.Upload{path: path, filename: "report.txt", content_type: "text/plain"}

    assert {:ok, %{"url" => url, "newFileName" => filename}} = Upload.store_file(upload)
    assert url == "/profile/upload/" <> filename

    assert {:error, :invalid_file_name} = Upload.resolve_download_path("../secret.txt")
    assert {:error, :type_not_allowed} = Upload.resolve_download_path("secret.sh")

    conn =
      ResourceController.show(conn(:get, url), %{"path" => ["upload", filename]})

    assert conn.status == 200
    assert conn.resp_body == "hello"
    File.rm!(path)
  end

  test "stores a batch of generic files" do
    first = temporary_file("first.txt", "one")
    second = temporary_file("second.pdf", "two")

    uploads = [
      %Plug.Upload{path: first, filename: "first.txt", content_type: "text/plain"},
      %Plug.Upload{path: second, filename: "second.pdf", content_type: "application/pdf"}
    ]

    assert {:ok, stored} = Upload.store_files(uploads)
    assert length(stored) == 2
    File.rm!(first)
    File.rm!(second)
  end

  defp temporary_file(filename, content) do
    path =
      Path.join(
        System.tmp_dir!(),
        "keystone-upload-#{System.unique_integer([:positive])}-#{filename}"
      )

    File.write!(path, content)
    path
  end
end
