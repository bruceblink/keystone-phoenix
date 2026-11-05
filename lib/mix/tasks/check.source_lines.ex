defmodule Mix.Tasks.Check.SourceLines do
  @moduledoc "Checks that repository source files stay within the configured line limit."

  use Mix.Task

  @shortdoc "Checks source file line counts"
  @max_lines 600
  @roots ~w(lib config priv test)
  @extensions ~w(.ex .exs .eex)

  @impl Mix.Task
  def run(_args) do
    violations =
      @roots
      |> Enum.flat_map(&source_files/1)
      |> Enum.map(&{&1, line_count(&1)})
      |> Enum.filter(fn {_path, lines} -> lines > @max_lines end)

    case violations do
      [] ->
        Mix.shell().info("Source line limit OK (<= #{@max_lines} lines).")

      violations ->
        details = Enum.map_join(violations, "\n", fn {path, lines} -> "#{lines} #{path}" end)
        Mix.raise("Source files must contain no more than #{@max_lines} lines:\n#{details}")
    end
  end

  defp source_files(root) do
    if File.dir?(root) do
      root
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.filter(fn path -> Path.extname(path) in @extensions end)
    else
      []
    end
  end

  defp line_count(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: false)
    |> length()
  end
end
