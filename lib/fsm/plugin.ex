defmodule FSM.Plugin do
  @moduledoc """
  Plugin behavior for FSM plugins.
  """

  @callback init(fsm :: struct(), opts :: keyword()) :: struct()
  @callback before_transition(fsm :: struct(), transition_data :: tuple(), opts :: keyword()) :: struct()
  @callback after_transition(fsm :: struct(), transition_data :: tuple(), opts :: keyword()) :: struct()

  defmacro __using__(_) do
    quote do
      @behaviour FSM.Plugin

      def init(fsm, _opts), do: fsm
      def before_transition(fsm, _data, _opts), do: fsm
      def after_transition(fsm, _data, _opts), do: fsm

      defoverridable [init: 2, before_transition: 3, after_transition: 3]
    end
  end
end
