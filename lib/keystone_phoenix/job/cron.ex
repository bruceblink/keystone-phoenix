defmodule KeystonePhoenix.Job.Cron do
  @moduledoc "Small six-field Cron validator and matcher for scheduled jobs."

  @ranges [{0, 59}, {0, 59}, {0, 23}, {1, 31}, {1, 12}, {0, 7}]

  @doc "Validates a Spring-style six-field Cron expression."
  def validate(expression) when is_binary(expression) do
    case parse(expression) do
      {:ok, _fields} -> :ok
      {:error, _reason} = error -> error
    end
  end

  def validate(_expression), do: {:error, :invalid_expression}

  @doc "Returns whether a six-field Cron expression matches a UTC DateTime."
  def matches?(expression, %DateTime{} = datetime) do
    with {:ok, fields} <- parse(expression),
         values <- [
           datetime.second,
           datetime.minute,
           datetime.hour,
           datetime.day,
           datetime.month,
           rem(Date.day_of_week(DateTime.to_date(datetime)), 7)
         ] do
      Enum.zip(fields, values) |> Enum.all?(fn {field, value} -> value in field end)
    else
      _ -> false
    end
  end

  def matches?(_expression, _datetime), do: false

  defp parse(expression) do
    fields = String.split(String.trim(expression), ~r/\s+/, trim: true)

    if length(fields) != 6 do
      {:error, :expected_six_fields}
    else
      fields
      |> Enum.zip(@ranges)
      |> Enum.reduce_while({:ok, []}, fn {field, {min, max}}, {:ok, parsed} ->
        case parse_field(field, min, max) do
          {:ok, values} -> {:cont, {:ok, [values | parsed]}}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
      |> reverse_fields()
    end
  end

  defp reverse_fields({:ok, fields}), do: {:ok, Enum.reverse(fields)}
  defp reverse_fields(error), do: error

  defp parse_field(field, min, max) when is_binary(field) and field != "" do
    field
    |> String.split(",", trim: true)
    |> Enum.reduce_while({:ok, MapSet.new()}, fn part, {:ok, values} ->
      case parse_part(part, min, max) do
        {:ok, part_values} ->
          {:cont, {:ok, Enum.reduce(part_values, values, &MapSet.put(&2, &1))}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, values} when map_size(values) > 0 -> {:ok, MapSet.to_list(values)}
      {:ok, _values} -> {:error, :empty_field}
      error -> error
    end
  end

  defp parse_field(_field, _min, _max), do: {:error, :empty_field}

  defp parse_part(part, min, max) do
    case String.split(part, "/", parts: 2) do
      [base, step] ->
        with {:ok, step} <- positive_integer(step),
             {:ok, start, finish} <- parse_base(base, min, max) do
          {:ok, Enum.take_every(start..finish, step)}
        end

      [base] ->
        with {:ok, start, finish} <- parse_base(base, min, max) do
          {:ok, Enum.to_list(start..finish)}
        end

      _ ->
        {:error, :invalid_step}
    end
  end

  defp parse_base(base, min, max) when base in ["*", "?"] do
    {:ok, min, max}
  end

  defp parse_base(base, min, max) do
    case String.split(base, "-", parts: 2) do
      [first, last] ->
        with {:ok, first} <- bounded_integer(first, min, max),
             {:ok, last} <- bounded_integer(last, min, max),
             true <- first <= last do
          {:ok, first, last}
        else
          _ -> {:error, :invalid_range}
        end

      [single] ->
        with {:ok, value} <- bounded_integer(single, min, max) do
          {:ok, value, value}
        end

      _ ->
        {:error, :invalid_value}
    end
  end

  defp positive_integer(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> {:ok, number}
      _ -> {:error, :invalid_step}
    end
  end

  defp bounded_integer(value, min, max) do
    case Integer.parse(value) do
      {number, ""} when number >= min and number <= max -> {:ok, number}
      _ -> {:error, :out_of_range}
    end
  end
end
