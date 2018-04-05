# Wrapper around SSH that allows running commands.
defmodule Elsh.Connection do
  defstruct host: nil, ssh_options: {}, conn_id: nil

  # Connects to a %Elsh.Host{}.
  #
  # @param host [%Elsh.Host{}]
  # @return [%Elsh.Connection{}]
  def connect(host, ssh_port \\ 22, timeout \\ 30) do
    :ok = :ssh.start()
    {:ok, pid} = :ssh.connect(host.label, ssh_port, [])

    %Elsh.Connection{host: host, conn_id: pid, ssh_options: %{port: ssh_port, timeout: timeout}}
  end

  # Runs a command on the remote host, contained in +conn+.
  #
  # @param conn [%Elsh.Connection{}]
  # @param command [String]
  # @return [{:ok, String, Integer}] Where +String+ is the stdout/stderr text
  #   returned from command; +Integer+ is the status code resulting from the
  #   command.
  def exec(conn, command) when is_binary(command) do
    command = String.to_char_list(command)
    run(conn, command)
  end

  def exec(conn, command) do
    run(conn, command)
  end

  # Runs a command on the remote host, contained in +conn+.
  #
  # @param conn [%Elsh.Connection{}]
  # @param command [String]
  # @return [{:ok, String, Integer}] Where +String+ is the stdout/stderr text
  #   returned from command; +Integer+ is the status code resulting from the
  #   command.
  def run(conn, command) do
    case open_channel_and_exec(conn, command) do
      {:error, response} -> {:error, response}
      channel_id -> get_response(conn, channel_id, "", "", nil, false)
    end
  end

  #----------------------------------------------------------------------------
  # PRIVATES
  #----------------------------------------------------------------------------

  defp open_channel_and_exec(conn, command) do
    case :ssh_connection.session_channel(conn.conn_id, conn.ssh_options.timeout) do
      {:error, response} -> {:error, response}
      {:ok, channel_id} ->
        IO.puts "ocae: #{channel_id}"
        :ssh_connection.exec(conn.conn_id, channel_id, command, conn.ssh_options.timeout)
        channel_id
    end
  end

  defp get_response(conn, channel_id, stdout, stderr, status, closed) do
    parsed = case {status, closed} do
      {st, true} when not is_nil(st) -> format_response({:ok, stdout, stderr, status})
      _ -> receive_and_parse(conn, channel_id, stdout, stderr, status, closed)
    end

    case parsed do
      {:loop, {ch, _timeout, out, err, st, cl}} ->
        get_response(conn, ch, out, err, st, cl)
      x -> x
    end
  end

  defp receive_and_parse(conn, channel_id, stdout, stderr, status, closed) do
    tout = conn.ssh_options.timeout

    response = receive do
      {:ssh_cm, _, res} -> res
    after
      conn.ssh_options.timeout ->
        {:error, "Timeout. Did not receive data for #{conn.ssh_options.timeout}ms."}
    end

    # call adjust_window to allow more data income, but only when needed
    case response do
      {:data, ^channel_id, _, new_data} ->
        :ssh_connection.adjust_window(conn.conn_id, channel_id, byte_size(new_data))
      _ -> :ok
    end

    case response do
      {:data, ^channel_id, 1, new_data} ->       {:loop, {channel_id, tout, stdout, stderr <> new_data, status, closed}}
      {:data, ^channel_id, 0, new_data} ->       {:loop, {channel_id, tout, stdout <> new_data, stderr, status, closed}}
      {:eof, ^channel_id} ->                     {:loop, {channel_id, tout, stdout, stderr, status, closed}}
      {:exit_signal, ^channel_id, _, _} ->       {:loop, {channel_id, tout, stdout, stderr, status, closed}}
      {:exit_status, ^channel_id, new_status} -> {:loop, {channel_id, tout, stdout, stderr, new_status, closed}}
      {:closed, ^channel_id} ->                  {:loop, {channel_id, tout, stdout, stderr, status, true}}
      any -> any # {:error, reason}
    end
  end

  defp format_response(raw) do
    {:ok, stdout, stderr, status} = raw
    {:ok, stdout <> stderr, status}
  end
end
