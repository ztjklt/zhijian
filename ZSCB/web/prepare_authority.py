"""Add optional motion reconciliation metadata to a frozen authority.

No simulation rules, input authority, protocol version or persistence change.
Matching-protocol clients ignore the optional fields; no client position is accepted.
"""
from pathlib import Path

def replace_once(text,old,new):
    if text.count(old)!=1:raise ValueError('Fixed r2 authority anchor changed: '+old[:90])
    return text.replace(old,new,1)

def prepare_authority(project:Path):
    actor=project/'scripts/net/actor.gd'
    text=actor.read_text()
    # Native sources already include this optional metadata. Reject partial ports.
    if 'var movement_reset := 0' in text:
        required=['"input_ack":input_seq','"input_age":input_age','"movement_reset":movement_reset',
                  'func set_active(active: bool) -> void:\n\tmovement_reset += 1']
        if not all(part in text for part in required) or 'actor.movement_reset += 1' not in (project/'scripts/net/room.gd').read_text():
            raise ValueError('Incomplete native movement ACK metadata')
        return
    text=replace_once(text,'var input_seq := 0','var input_seq := 0\nvar movement_reset := 0')
    text=replace_once(text,'func set_active(active: bool) -> void:','func set_active(active: bool) -> void:\n\tmovement_reset += 1')
    text=replace_once(text,'\t\tplayer.position = spawn\n\t\tPhysicsServer2D.body_set_state', '\t\tmovement_reset += 1\n\t\tplayer.position = spawn\n\t\tPhysicsServer2D.body_set_state')
    text=replace_once(text,'return {"id":player_id,"name":display_name,','return {"input_ack":input_seq,"input_age":input_age,"movement_reset":movement_reset,"id":player_id,"name":display_name,')
    actor.write_text(text)
    room=project/'scripts/net/room.gd'
    text=replace_once(room.read_text(),'\t\t\tactor.player.position = spawn\n', '\t\t\tactor.movement_reset += 1\n\t\t\tactor.player.position = spawn\n')
    room.write_text(text)
