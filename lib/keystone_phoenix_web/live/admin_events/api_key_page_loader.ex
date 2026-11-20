defmodule KeystonePhoenixWeb.Live.AdminEvents.ApiKeyPageLoader do
  @moduledoc "Keeps paged API Key reads within the current result range."

  # 最后一页记录被删除或到期后，总数可能已不足以容纳原页码；最多重读一次新末页。
  def load(read_page, requested_page) when is_function(read_page, 1) do
    case read_page.(requested_page) do
      {:ok, result} ->
        last_page = last_page(result.total, result.size)

        if result.page > last_page,
          do: read_last_page(read_page, last_page),
          else: {:ok, result}

      {:error, _reason} = error ->
        error
    end
  end

  defp read_last_page(read_page, last_page) do
    case read_page.(last_page) do
      {:ok, result} ->
        if result.page > last_page(result.total, result.size),
          do: {:error, :resource_conflict},
          else: {:ok, result}

      {:error, _reason} = error ->
        error
    end
  end

  defp last_page(total, size), do: max(div(total + size - 1, size), 1)
end
