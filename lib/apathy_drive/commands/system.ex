defmodule ApathyDrive.Commands.System do
  use ApathyDrive.Command
  require Ecto.Query
  alias ApathyDrive.{Area, Mobile, PubSub, Repo, Room}

  def keywords, do: ["system", "sys"]

  def execute(mobile, []) do
    Mobile.send_scroll(mobile, "<p>Invalid system command.</p>")
  end

  def execute(mobile, args) when is_pid(mobile) do
    Mobile.system(mobile, args)
  end

  def execute(%Mobile{socket: socket, spirit: %Spirit{admin: true}, room_id: room_id}, ["edit", "room"]) do
    send(socket, {:open_tab, "/admin/rooms/#{room_id}"})
  end

  def execute(%Mobile{spirit: %Spirit{admin: true}, room_id: room_id}, args) do
    room_id
    |> RoomServer.find
    |> RoomServer.system(self, args)
  end

  def execute(%Mobile{} = mobile, _args) do
    Mobile.send_scroll(mobile, "<p>You do not have permission to do that.</p>")
  end

  def execute(%Room{area: %Area{level: old_level} = area} = room, mobile, ["set", "area", "level", level]) do
    area = Area.update_level(area, level)
    PubSub.broadcast!("areas:#{area.id}", {:update_area, area})
    Mobile.send_scroll(mobile, "<p>#{area.name} updated from level #{old_level} to #{level}.</p>")
    room
  end

  def execute(room, mobile, ["invis"]) do
    Mobile.toggle_invisibility(mobile)
    room
  end

  def execute(%Room{area: %Area{} = old_area} = room, mobile, ["merge", "area" | area]) do
    area = Enum.join(area, " ")

    area
    |> Area.find_by_name
    |> Repo.one
    |> case do
         %Area{} = area ->
           PubSub.broadcast!("areas:#{old_area.id}", {:update_area, area})
           Mobile.send_scroll(mobile, "<p>#{old_area.name} merged into #{area.name}.</p>")
           room
         nil ->
           Mobile.send_scroll(mobile, "<p>Could not find an area named \"#{area}\".")
           room
       end
  end

  def execute(%Room{area: %Area{} = old_area} = room, mobile, ["set", "area" | area]) do
    area = Enum.join(area, " ")

    area
    |> Area.find_by_name
    |> Repo.one
    |> case do
         %Area{} = area ->
           room = Room.update_area(room, area)

           Mobile.send_scroll(mobile, "<p>Area changed from \"#{old_area.name}\"(#{old_area.level}) to \"#{room.area.name}\"(#{room.area.level}).</p>")
           room
         nil ->
           Mobile.send_scroll(mobile, "<p>Could not find an area named \"#{area}\".")
           room
       end
  end

  def execute(%Room{} = room, mobile, ["create", "area" | area]) do
    area = Enum.join(area, " ")

    area
    |> Area.changeset
    |> Repo.insert
    |> case do
         {:ok, %Area{name: name} = area} ->
           room = Room.update_area(room, area)
           Mobile.send_scroll(mobile, "<p>\"#{name}\" created!</p>")
           room
         {:error, %Ecto.Changeset{errors: errors}} ->
           Enum.each(errors, fn {field, error} ->
             message = ApathyDrive.ErrorHelpers.translate_error(error)
             Mobile.send_scroll(mobile, "<p>Error: #{field} #{message}</p>")
           end)
           room
       end
  end

  def execute(%Room{name: old_name} = room, mobile, ["set", "room", "name" | room_name]) do
    room =
      room
      |> Map.put(:name, Enum.join(room_name, " "))
      |> Repo.save!

    ApathyDrive.Endpoint.broadcast!("map", "room name change", %{room_id: room.id, name: room.name})

    Mobile.send_scroll(mobile, "<p>Room name changed from \"#{old_name}\" to \"#{room.name}\".</p>")

    room
  end

  def execute(%Room{coordinates: old_coords} = room, mobile, ["set", "room", "coords", x, y, z]) do
    x = String.to_integer(x)
    y = String.to_integer(y)
    z = String.to_integer(z)

    room =
      room
      |> Map.put(:coordinates, %{"x" => x, "y" => y, "z" => z})
      |> Repo.save!

    ApathyDrive.Endpoint.broadcast!("map", "room coords change", %{room_id: room.id, x: x, y: y, z: z})

    Mobile.send_scroll(mobile, "<p>Room coordinates changed from \"#{inspect(old_coords)}\" to \"#{inspect(room.coordinates)}\".</p>")

    room
  end

  def execute(%Room{} = room, mobile, ["list", "areas"]) do
    Area.list_with_room_counts
    |> Repo.all
    |> Enum.chunk(10)
    |> Enum.each(fn chunk ->
         Mobile.send_scroll(mobile, "<p><span class='dark-magenta'>Level</span> <span class='dark-green'>|</span> <span class='dark-magenta'>Rooms</span> <span class='dark-green'>|</span> <span class='dark-magenta'>Area</span></p>")
         Enum.each(chunk, fn [area, room_count] ->
           Mobile.send_scroll(mobile, "<p><span class='dark-cyan'>#{to_string(area.level) |> String.rjust(5)}</span> <span class='dark-green'>|</span> <span class='dark-cyan'>#{to_string(room_count) |> String.rjust(5)}</span> <span class='dark-green'>|</span> <span class='black'>#{area.name}</span></p>")
         end)

       end)
    room
  end

  def execute(%Room{} = room, mobile, ["goto" | area]) do
    area = Enum.join(area, " ")


    area
    |> Area.find_by_name
    |> Repo.one
    |> case do
         %Area{} = area ->
           Ecto.assoc(area, :rooms)
           |> Ecto.Query.limit(1)
           |> Ecto.Query.select([:id])
           |> ApathyDrive.Repo.one
           |> case do
                %Room{id: room_id} ->
                  Mobile.teleport(mobile, room_id)
                _ ->
                  Mobile.send_scroll(mobile, "<p>#{area.name} has no rooms!</p>")
              end


           room
         nil ->
           Mobile.send_scroll(mobile, "<p>Could not find an area named \"#{area}\".")
           room
       end
  end

  def execute(%Room{} = room, mobile, _args) do
    Mobile.send_scroll(mobile, "<p>Invalid system command.</p>")

    room
  end

end
