defmodule KeystonePhoenix.Upload do
  @moduledoc "Local file storage boundary for profile uploads."

  @max_file_size 50 * 1024 * 1024
  @max_filename_length 127
  @allowed_extensions ~w(bmp gif jpg jpeg png doc docx xls xlsx ppt pptx html htm txt rar zip gz bz2 mp4 avi rmvb pdf)

  @spec store_avatar(Plug.Upload.t()) :: {:ok, String.t()} | {:error, atom()}
  def store_avatar(%Plug.Upload{} = upload) do
    with {:ok, stat} <- File.stat(upload.path),
         :ok <- validate_size(stat.size),
         :ok <- validate_filename(upload.filename),
         {:ok, extension} <- extension(upload),
         filename <- generated_filename(upload.filename, extension),
         directory <- Path.join(base_dir(), "avatar"),
         :ok <- File.mkdir_p(directory),
         :ok <- copy_file(upload.path, Path.join(directory, filename)) do
      {:ok, "/profile/avatar/#{filename}"}
    else
      {:error, reason} when reason in [:enoent, :eacces, :enospc] -> {:error, :storage_error}
      {:error, reason} -> {:error, reason}
    end
  end

  def store_avatar(_upload), do: {:error, :invalid_upload}

  @spec resolve_profile_path(list()) :: {:ok, String.t()} | {:error, :not_found}
  def resolve_profile_path(path_segments) when is_list(path_segments) do
    root = Path.expand(base_dir())
    path = Path.expand(Path.join([root | path_segments]))

    if path != root and String.starts_with?(path, root <> "/") and File.regular?(path) do
      {:ok, path}
    else
      {:error, :not_found}
    end
  end

  def resolve_profile_path(_path_segments), do: {:error, :not_found}

  defp base_dir do
    Application.get_env(:keystone_phoenix, :file_base_dir, "uploads")
    |> Path.expand()
  end

  defp validate_size(0), do: {:error, :empty_upload}
  defp validate_size(size) when size > @max_file_size, do: {:error, :file_too_large}
  defp validate_size(_size), do: :ok

  defp validate_filename(filename) when is_binary(filename) do
    if String.length(filename) <= @max_filename_length do
      :ok
    else
      {:error, :filename_too_long}
    end
  end

  defp validate_filename(_filename), do: {:error, :invalid_upload}

  defp extension(%Plug.Upload{filename: filename, content_type: content_type}) do
    extension = filename |> Path.extname() |> String.trim_leading(".") |> String.downcase()
    extension = if extension == "", do: content_type_extension(content_type), else: extension

    if extension in @allowed_extensions do
      {:ok, extension}
    else
      {:error, :type_not_allowed}
    end
  end

  defp content_type_extension(content_type) when is_binary(content_type) do
    case MIME.extensions(content_type) do
      [extension | _] -> String.downcase(extension)
      _ -> ""
    end
  end

  defp content_type_extension(_content_type), do: ""

  defp generated_filename(original_filename, extension) do
    base_name =
      original_filename
      |> Path.basename()
      |> Path.rootname()
      |> String.replace(~r/[^A-Za-z0-9_-]/u, "_")
      |> String.slice(0, 80)

    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d%H%M%S")
    random = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    "#{timestamp}_#{base_name}_#{random}.#{extension}"
  end

  defp copy_file(source, destination) do
    case File.cp(source, destination) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
