defmodule ApathyDrive.Repo.Migrations.AddUnityToSpiritsAndMonsters do
  use Ecto.Migration

  def change do
    alter table(:monsters) do
      add :unity, :text
    end
    alter table(:spirits) do
      add :unity, :text
    end
  end
end
