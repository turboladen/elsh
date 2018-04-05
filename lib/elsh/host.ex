defmodule Elsh.Host do
  defstruct label: 'localhost', operating_system: nil

  def get_operating_system(conn) do
    case Elsh.Connection.run(conn, 'uname -a') do
      {:ok, result, _status} ->
        String.strip(result)
        IO.puts "result: #{result}"

        new_host = %Elsh.Host{} |> Map.merge(conn.host)
        new_host = %{new_host | operating_system: String.strip(result)}
        new_conn = %{conn | host: new_host}

        {:ok, new_conn}
      x -> x
    end
  end

  def name(conn) do
    case Elsh.Connection.run(conn, 'hostname') do
      {:ok, result, _status} ->
        String.strip(result)
      x -> x
    end
  end
end
