defmodule Elsh.Host do
  defstruct label: 'localhost', operating_system: nil

  def get_operating_system(host) do
    {result, _status} = System.cmd("uname", ["-a"])
    IO.puts "result: #{result}"

    new_host = %Elsh.Host{} |> Map.merge(host)
    new_host = %{new_host | operating_system: String.strip(result)}

    {:ok, new_host}
  end

  def name(_host) do
    {result, _status} = System.cmd("hostname", [])

    String.strip(result)
  end
end
