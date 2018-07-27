defmodule Coney.ConsumerExecutor do
  alias Coney.{ConnectionServer, ExecutionTask, ConsumerConnection}

  def consume(
        %ExecutionTask{consumer: consumer, connection: connection, payload: payload, meta: meta} =
          task
      ) do
    try do
      payload
      |> consumer.parse(meta)
      |> consumer.process(meta)
      |> handle_result(consumer, connection, task)
    rescue
      exception ->
        if function_exported?(consumer, :error_happened, 3) do
          exception
          |> consumer.error_happened(payload, meta)
          |> handle_result(consumer, connection, task)
        else
          reject(consumer, connection, task)
        end
    end
  end

  defp handle_result(result, consumer, connection, task) do
    case result do
      :ok ->
        ack(consumer, connection, task)

      :reject ->
        reject(consumer, connection, task)

      :redeliver ->
        redeliver(consumer, connection, task)

      {:reply, response} ->
        reply(consumer, response, connection, task)
    end
  end

  defp ack(consumer, connection, %ExecutionTask{tag: tag}) do
    ConnectionServer.confirm(connection.subscribe_channel, tag)
  end

  defp reply(
         consumer,
         response,
         %ConsumerConnection{publish_channel: publish_channel} = connection,
         %ExecutionTask{tag: tag} = task
       ) do
    ack(consumer, connection, task)

    exchange_name = elem(consumer.connection.respond_to, 1)
    send_message(publish_channel, exchange_name, response)
  end

  defp redeliver(
         consumer,
         %ConsumerConnection{subscribe_channel: subscribe_channel},
         %ExecutionTask{tag: tag}
       ) do
    ConnectionServer.reject(subscribe_channel, tag, true)
  end

  defp reject(consumer, %ConsumerConnection{subscribe_channel: subscribe_channel}, %ExecutionTask{
         tag: tag
       }) do
    ConnectionServer.reject(subscribe_channel, tag, false)
  end

  defp send_message(channel, exchange, {routing_key, response}) do
    ConnectionServer.publish(channel, exchange, routing_key, response)
  end

  defp send_message(channel, exchange, response) do
    send_message(channel, exchange, {"", response})
  end
end
