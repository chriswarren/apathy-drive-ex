defmodule ApathyDrive.Repo.Migrations.AddSpawnedAtToMonsters do
  use Ecto.Migration

  def change do
    alter table(:monsters) do
      add :spawned_at, :integer
    end
  end
end
