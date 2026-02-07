# ~/Core/GameState/game_phase.gd
class_name GamePhaseEnum
extends Node

#Hold the game state. 
#Briefing is preview of map,
#Planning allows action planning,
#Executing allows action and game flow,
#Debrief allows game end and or backlog.
enum GamePhase {
	BRIEFING,
	PLANNING,
	EXECUTING,
	DEBRIEFING
}
