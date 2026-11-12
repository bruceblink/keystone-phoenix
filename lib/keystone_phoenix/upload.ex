defmodule KeystonePhoenix.Upload do
  @moduledoc "Local file storage boundary for profile uploads."

  @max_file_size 50 * 1024 * 1024
  @max_batch_size 100 * 1024 * 1024
  @max_filename_length 127
  @max_batch_entries 20
  @allowed_extensions ~w(bmp gif jpg jpeg png webp)
  @file_extensions ~w(bmp gif jpg jpeg png doc docx xls xlsx ppt pptx html htm txt rar zip gz bz2 mp4 avi rmvb pdf)

  @doc "Stores one generic file under the upload resource directory."
  @spec store_file(Plug.Upload.t()) :: {:ok, map()} | {:error, atom()}
  def store_file(upload), do: store_file(upload, nil)

  @spec store_file(Plug.Upload.t(), pos_integer() | nil) :: {:ok, map()} | {:error, atom()}
  def store_file(%Plug.Upload{} = upload, owner_id) do
    with {:ok, filename, extension} <- validate_generic_upload(upload),
         directory <- upload_directory(owner_id),
         :ok <- File.mkdir_p(directory),
         destination <- Path.join(directory, filename),
         :ok <- copy_file(upload.path, destination) do
      relative = upload_relative_path(owner_id, filename)

      {:ok,
       %{
         "url" => relative,
         "fileName" => relative,
         "newFileName" => filename,
         "originalFilename" => upload.filename,
         "extension" => extension
       }}
    else
      {:error, reason} when reason in [:enoent, :eacces, :enospc] -> {:error, :storage_error}
      {:error, reason} -> {:error, reason}
    end
  end

  def store_file(_upload, _owner_id), do: {:error, :invalid_upload}

  @doc "Stores a batch of generic files under one owner's namespace."
  @spec store_files(list()) :: {:ok, list(map())} | {:error, atom()}
  def store_files(uploads), do: store_files(uploads, nil)

  @spec store_files(list(), pos_integer() | nil) :: {:ok, list(map())} | {:error, atom()}
  def store_files(uploads, owner_id)

  def store_files(uploads, owner_id)
      when is_list(uploads) and uploads != [] and length(uploads) <= @max_batch_entries do
    with :ok <- validate_batch_size(uploads) do
      Enum.reduce_while(uploads, {:ok, []}, fn upload, {:ok, stored} ->
        case store_file(upload, owner_id) do
          {:ok, file} -> {:cont, {:ok, [file | stored]}}
          {:error, reason} -> {:halt, {:error, reason, stored}}
        end
      end)
      |> case do
        {:ok, stored} ->
          {:ok, Enum.reverse(stored)}

        {:error, reason, stored} ->
          cleanup_stored_files(stored)
          {:error, reason}
      end
    end
  end

  def store_files(uploads, _owner_id)
      when is_list(uploads) and length(uploads) > @max_batch_entries,
      do: {:error, :too_many_files}

  def store_files(_uploads, _owner_id), do: {:error, :empty_upload}

  defp upload_directory(nil), do: Path.join(base_dir(), "upload")

  defp upload_directory(owner_id),
    do: Path.join([base_dir(), "upload", Integer.to_string(owner_id)])

  defp upload_relative_path(nil, filename), do: "/profile/upload/#{filename}"
  defp upload_relative_path(owner_id, filename), do: "/profile/upload/#{owner_id}/#{filename}"

  defp validate_batch_size(uploads) do
    Enum.reduce_while(uploads, 0, fn
      %Plug.Upload{path: path}, total ->
        case File.stat(path) do
          {:ok, %{size: size}} when total + size <= @max_batch_size ->
            {:cont, total + size}

          {:ok, %{size: _size}} ->
            {:halt, {:error, :batch_too_large}}

          {:error, reason} when reason in [:enoent, :eacces, :enospc] ->
            {:halt, {:error, :storage_error}}

          {:error, _reason} ->
            {:halt, {:error, :invalid_upload}}
        end

      _upload, _total ->
        {:halt, {:error, :invalid_upload}}
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      _total -> :ok
    end
  end

  @doc "Resolves a generic download resource while preventing path traversal."
  @spec resolve_download_path(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def resolve_download_path(file_name) when is_binary(file_name) do
    cond do
      file_name == "" or String.contains?(file_name, ["..", "\\", "\n", "\r"]) ->
        {:error, :invalid_file_name}

      (Path.extname(file_name)
       |> String.trim_leading(".")
       |> String.downcase()) not in @file_extensions ->
        {:error, :type_not_allowed}

      true ->
        root = Path.expand(Path.join(base_dir(), "download"))
        path = Path.expand(Path.join(root, file_name))

        if String.starts_with?(path, root <> "/") and File.regular?(path),
          do: {:ok, path},
          else: {:error, :not_found}
    end
  end

  def resolve_download_path(_file_name), do: {:error, :invalid_file_name}

  @doc "Returns generic file extensions accepted by the original Keystone API."
  def allowed_file_extensions, do: @file_extensions

  @spec store_avatar(Plug.Upload.t()) :: {:ok, String.t()} | {:error, atom()}
  def store_avatar(%Plug.Upload{} = upload) do
    with {:ok, stat} <- File.stat(upload.path),
         :ok <- validate_size(stat.size),
         :ok <- validate_filename(upload.filename),
         {:ok, extension} <- extension(upload),
         :ok <- validate_signature(upload.path, extension),
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

  @doc "Deletes a previously stored local avatar after a database write fails."
  @spec delete_avatar(String.t()) :: :ok
  def delete_avatar(url) when is_binary(url) do
    path = String.split(String.trim_leading(url, "/"), "/", trim: true)

    case resolve_profile_path(path) do
      {:ok, path} ->
        _ = File.rm(path)
        :ok

      {:error, :not_found} ->
        :ok
    end
  end

  def delete_avatar(_url), do: :ok

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

  defp validate_generic_upload(%Plug.Upload{} = upload) do
    with {:ok, stat} <- File.stat(upload.path),
         :ok <- validate_size(stat.size),
         :ok <- validate_filename(upload.filename),
         {:ok, extension} <- generic_extension(upload),
         filename <- generated_filename(upload.filename, extension) do
      {:ok, filename, extension}
    else
      {:error, reason} when reason in [:enoent, :eacces, :enospc] -> {:error, :storage_error}
      {:error, reason} -> {:error, reason}
    end
  end

  defp generic_extension(%Plug.Upload{filename: filename, content_type: content_type}) do
    extension = filename |> Path.extname() |> String.trim_leading(".") |> String.downcase()
    extension = if extension == "", do: content_type_extension(content_type), else: extension

    if extension in @file_extensions, do: {:ok, extension}, else: {:error, :type_not_allowed}
  end

  defp content_type_extension(content_type) when is_binary(content_type) do
    case MIME.extensions(content_type) do
      [extension | _] -> String.downcase(extension)
      _ -> ""
    end
  end

  defp content_type_extension(_content_type), do: ""

  defp validate_signature(path, extension) do
    case File.open(path, [:read, :binary], fn io -> IO.binread(io, 12) end) do
      {:ok, signature} ->
        if valid_signature?(extension, signature), do: :ok, else: {:error, :type_not_allowed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp valid_signature?("jpg", <<0xFF, 0xD8, 0xFF, _rest::binary>>), do: true
  defp valid_signature?("jpeg", <<0xFF, 0xD8, 0xFF, _rest::binary>>), do: true
  defp valid_signature?("png", <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _rest::binary>>), do: true
  defp valid_signature?("gif", <<"GIF87a", _rest::binary>>), do: true
  defp valid_signature?("gif", <<"GIF89a", _rest::binary>>), do: true
  defp valid_signature?("bmp", <<"BM", _rest::binary>>), do: true

  defp valid_signature?("webp", <<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>),
    do: true

  defp valid_signature?(_extension, _signature), do: false

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

  defp cleanup_stored_files(stored) do
    Enum.each(stored, fn %{"newFileName" => filename} ->
      _ = File.rm(Path.join([base_dir(), "upload", filename]))
    end)
  end
end
