defmodule KeystonePhoenix.Params do
  @moduledoc "Small helpers for parsing request parameters at domain boundaries."

  @spec parse_integer(term()) :: {:ok, integer()} | :error
  def parse_integer(value) when is_integer(value), do: {:ok, value}

  def parse_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} -> {:ok, integer}
      _ -> :error
    end
  end

  def parse_integer(_value), do: :error

  @spec parse_positive_integer(term()) :: {:ok, pos_integer()} | :error
  def parse_positive_integer(value) do
    case parse_integer(value) do
      {:ok, integer} when integer > 0 -> {:ok, integer}
      _ -> :error
    end
  end

  @spec non_negative_integer(term()) :: {:ok, non_neg_integer()} | :error
  def non_negative_integer(nil), do: {:ok, 0}

  def non_negative_integer(value) do
    case parse_integer(value) do
      {:ok, integer} when integer >= 0 -> {:ok, integer}
      _ -> :error
    end
  end
end
