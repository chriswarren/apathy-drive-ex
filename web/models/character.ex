defmodule ApathyDrive.Character do
  use ApathyDrive.Web, :model

  schema "characters" do
    field :name, :string
    field :race_id, :integer
    field :class_id, :integer
    field :experience, :integer
    field :alignment, :integer

    belongs_to :player, ApathyDrive.Player

    timestamps
  end

  @required_fields ~w(name race_id class_id experience alignment)
  @optional_fields ~w()

  @doc """
  Creates a changeset based on the `model` and `params`.

  If no params are provided, an invalid changeset is returned
  with no validation performed.
  """
  def changeset(model, params \\ :empty) do
    model
    |> cast(params, @required_fields, @optional_fields)
  end
end
