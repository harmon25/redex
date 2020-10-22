defmodule Redex.TypespecParser do
  def to_ts(spec) do
    """
    type Actions = {
    #{
      actions(spec)
      |> Enum.map(fn {action, params} -> "  #{action}: #{_to_ts(params)}" end)
      |> Enum.join("\n")
    }
    }
    """
  end
  def _to_ts([]) do
    "{}"
  end
  def _to_ts(params) when is_list(params) do
    """
    {
    #{Enum.map(params, fn {key, type} -> "    #{key}: #{type}" end) |> Enum.join("\n")}
      }
    """
    |> String.trim_trailing()
  end
  def _to_ts(type) do
    type |> to_string
  end
  def actions([]) do
    []
  end
  def actions(specs) do
    specs
    |> Enum.filter(fn
      {:spec, {_, _, [{:action, _, _}, _]}, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {:spec, {_, _, [{:action, _, [{action_name, params}, _, _]}, _]}, _} ->
      {action_name, to_type(params)}
    end)
  end
  def to_type({:%{}, _, map_fields} = args) do
    IO.inspect(args)
    map_fields |> Enum.map(&to_type/1)
  end
  def to_type({key, value_type}) do
    {key, to_type(value_type)}
  end
  def to_type(nil) do
    :null
  end
  def to_type({:integer, _, []}) do
    :number
  end
  def to_type({:map, _, []}) do
    :Object
  end
  def to_type({{:., _, [{_, _, [:String]}, _]}, _, _}) do
    :string
  end
end
