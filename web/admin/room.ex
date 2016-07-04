defmodule ApathyDrive.ExAdmin.Room do
  use ExAdmin.Register

  register_resource ApathyDrive.Room do

    form room do
      inputs do

        input room, :name
        input room, :description
        input room, :light
        content do
          ~s(
          <div id="room_item_descriptions_input" class="form-group">
            <label class="col-sm-2 control-label" for="room_item_descriptions">
              Item Descriptions<abbr class="required" title="required">*</abbr>
            </label>
            <div class="col-sm-10">
              <textarea id="room_item_descriptions" name="room[item_descriptions]" class="json">#{Poison.encode!(room.item_descriptions)}</textarea>
            </div>
          </div>
          )
        end
        input room, :lair_size
        input room, :lair_frequency
        content do
          ~s(
          <div id="room_exits_input" class="form-group">
            <label class="col-sm-2 control-label" for="room_exits">
              Exits<abbr class="required" title="required">*</abbr>
            </label>
            <div class="col-sm-10">
              <textarea id="room_exits" name="room[exits]" class="json">#{Poison.encode!(room.exits)}</textarea>
            </div>
          </div>
          )
        end
        content do
          ~s(
          <div id="room_commands_input" class="form-group">
            <label class="col-sm-2 control-label" for="room_commands">
              Commands<abbr class="required" title="required">*</abbr>
            </label>
            <div class="col-sm-10">
              <textarea id="room_commands" name="room[commands]" class="json">#{Poison.encode!(room.commands)}</textarea>
            </div>
          </div>
          )
        end
        input room, :legacy_id
        content do
          ~s(
          <div id="room_coordinates_input" class="form-group">
            <label class="col-sm-2 control-label" for="room_coordinates">
              Coordinates<abbr class="required" title="required">*</abbr>
            </label>
            <div class="col-sm-10">
              <textarea id="room_coordinates" name="room[coordinates]" class="json">#{Poison.encode!(room.coordinates)}</textarea>
            </div>
          </div>
          )
        end

      end
    end

  end
end
