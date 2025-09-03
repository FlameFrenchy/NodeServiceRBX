------------------------
-- NODE       SERVICE --
------------------------
type Navigation_Settings= {
	Points :{},
	Display:boolean?,
	JP_Enabled:boolean?
}

local PFS = game:GetService("PathfindingService")
local DBS = game:GetService("DataStoreService")
local AnalysticStore = DBS:GetDataStore("Store")

local Time = 0
local Timer = 10
local function Log(ev: string, cat: string, val: number|string)
	if Timer >= Time then
		return
	end
	
	local data = AnalysticStore:GetAsync("Stats") or {}
	data[ev] = {
		Event = ev,
		Category = cat,
		Value = val
	}
	AnalysticStore:SetAsync("Stats", data)
	local NSSYNC:RBXScriptConnection -- RESERVED FOR NODE SERVICE SYNC
	NSSYNC = game:GetService("RunService").Heartbeat:Connect(function(h)
		Time += h
		
		if Timer <= Time then
			NSSYNC:Disconnect()
		end
	end)
end

local function Get(ev: string)
	local data = AnalysticStore:GetAsync("Stats")
	if data and data[ev] and data[ev].Value then
		--print("found key")
		return data[ev].Value
	else
		--warn("no key for ".. ev)
		Log(ev,"Stats", 1)
	end
	return 0
end


local AwaitTimer = 0
local Paths = {}
local function createOwnerPlaceholder()
	local ownerId = game.CreatorId
	
	return ownerId
end
local OwnerPlaceholder = createOwnerPlaceholder()

local NodeService = {}
NodeService.Nav_Settings = {
	--[[
		This defines only the default Navigation Settings.
	]]
	Points = {},  -- Needs 2 or more points.
	Display= false, -- Optional
	JP_Enabled = false, -- Optional
}
NodeService.PathContinuous = {
	--[[
		This is storing ALL Path tables that are TYPE: "CONTINUOUS" 
		their calling process is "CONT-(path number)" 
		Note because it's parallel it won't ever be the same, but to retrieve it's ID use the return of the continuous return if u use continuous path.
		--]]	
}
local PathContinuous = NodeService.PathContinuous

function NodeService.Print()
	return print("Success", Get("Success"), "Fail", Get("Fail"))
end

function NodeService.Compute(Configuration:Navigation_Settings)
	--print("[🆗] NODE SERVICE COMPUTING [", AwaitTimer, "s Await]")
	if not Configuration then
		return error("No configuration Provided. Please give one.")
	end
	local PointA = Configuration.Points[1]
	local PointB = Configuration.Points[2]
	local JumpEnabled = Configuration.JP_Enabled or false
	local DisplayPath = Configuration.Display or false
	--print(PointA, PointB)
	if not PointA or not PointB then
		warn("⚠️ NO POINTS PROVIDED")
		return
	end
	PointA = PointA.Position
	PointB = PointB.Position
	task.wait(AwaitTimer)
	local path = PFS:CreatePath({
		AgentRadius = 1,
		AgentHeight = 1,
		AgentCanJump = JumpEnabled,
		Costs = {
		},
	})

	local ItemFolder = workspace:FindFirstChild("PathResult")
	if not ItemFolder then
		ItemFolder = Instance.new("Folder", workspace)
		ItemFolder.Name = "PathResult"
	end

	-- Compute the path
	local success :boolean, errorMessage :string = pcall(function()
		path:ComputeAsync(PointA, PointB)
	end)

	if success and path.Status == Enum.PathStatus.Success then
		--print("[🆗] SUCCESS")
		local nodes = path:GetWaypoints()
		local Appending = {
			Name = "Path"..#Paths + 1,
			Childs = {},
		}

		-- Smoothing function (Catmull-Rom Spline Interpolation)
		local function interpolatePath(nodes)
			local smoothPath = {}

			-- Ensure there are enough nodes to interpolate
			if #nodes < 2 then return smoothPath end

			-- Interpolate between each adjacent pair of nodes
			for i = 1, #nodes - 1 do
				local wp :PathWaypoint = nodes[i]
								
				local p0 = nodes[i].Position
				local p1 = nodes[i + 1].Position
				local act = nodes[i].Action
				
				if p1.Y > p0.Y then
					act = Enum.PathWaypointAction.Jump
					print("comparing: ", p1.Y, " P0: ", p0.Y)
				else
					act = Enum.PathWaypointAction.Walk
				end
				task.wait(0.01)
				-- Add the start point of the segment as a waypoint
				table.insert(smoothPath, PathWaypoint.new(p0, act))

				-- Interpolate between the two points
				local steps = 4  -- Number of intermediate points (adjust for smoothness)
				for t = 1, steps - 1 do
					local alpha = t / steps
					local interpolatedPoint = p0:Lerp(p1, alpha)  -- Linear interpolation between p0 and p1
					local action = wp.Action
					-- Add the interpolated point as a waypoint
					local point = PathWaypoint.new(interpolatedPoint, action)
					
					table.insert(smoothPath, point)
				end
			end

			-- Add the final node as a waypoint
			table.insert(smoothPath, PathWaypoint.new(nodes[#nodes].Position))

			return smoothPath
		end




		-- Create smooth path from waypoints
		local smoothPath = interpolatePath(nodes)

		-- Display the smooth path if needed
		local function Render()
			for i, point in ipairs(smoothPath) do
				if DisplayPath then
					local attach = Instance.new("Part", ItemFolder)
					attach.Anchored = true
					attach.Color = point.Action == Enum.PathWaypointAction.Jump and Color3.new(0, 1, 1) or Color3.new(0, 1, 0)
					attach.Size = Vector3.one
					attach.Transparency = 0.5
					attach.Position = point.Position
					if smoothPath[i+1] then
						attach.Rotation = (point.Position - smoothPath[i+1].Position ).Unit
					end
					attach.CanCollide = false
					attach.Material = Enum.Material.Neon
					table.insert(Appending.Childs, attach)
				end
			end
		end
		Render()
		
		Log("Success", "Node Service", Get("Success") + 1 )
		table.insert(Paths, Appending)
		return smoothPath

	else
		Log("Fail", "Node Service", Get("Fail") + 1 )
		print("[❗] NODE FAILED TO GENERATE : ", errorMessage)
	end
end


function NodeService:MultiCompute(Nav_Settings:Navigation_Settings)
	if not Nav_Settings then
		return error("No Settings provided. Please provide one.")
	end
	local Blocks = Nav_Settings.Points
	local Show = Nav_Settings.Display or false
	local JumpEnabled = Nav_Settings.JP_Enabled or false
	if not Blocks then
		return error("No blocks provided.")
	end
	local points = {} :: {PathWaypoint}
	for i, block in Blocks do
		if Blocks[i+1] then
			local A = block
			local B = Blocks[i+1]
			local newSetting = Nav_Settings
			newSetting.Points = {
				A,
				B,
			}
			local nodes = NodeService.Compute(newSetting)

			if nodes then
				for _, node in nodes do
					table.insert(points, node)
				end
			end
		end
	end
	if points ~= {} then
		--print("Found path!", points)
	end
	return points
end

--[[
	DEPRECATED UNTIL NEXT VERSION
]]
function NodeService.Continuous(Block1 :BasePart, Block2 :BasePart, Time :number)
	local LatestPath = {}
	local ID = #PathContinuous + 1
	PathContinuous["CONT-"..ID] = {
		PATH = {},
		ENABLE = true
	}
	local newtable = PathContinuous["CONT-"..ID]
	
	
	local COMPUTE_CONNEXION :RBXScriptConnection
	COMPUTE_CONNEXION = game:GetService("RunService").Heartbeat:Connect(function(d)
		table.clear(LatestPath)
		
		if Time > 0 then
			Time -= d
			if newtable.ENABLE == true then
				local A = Block1.Position
				local B = Block2.Position
				Time -= d
				LatestPath = NodeService.Compute(A, B, false, true)
				table.clear(newtable.PATH)
				for _, child in LatestPath do
					table.insert(newtable.PATH, child)
				end
			else
				COMPUTE_CONNEXION:Disconnect()
				PathContinuous["CONT-".. ID] = nil
				print("Continuous path was DISABLED and Deleted.")
			end
		elseif Time == -1 then
			if newtable.ENABLE == true then
				local A = Block1.Position
				local B = Block2.Position
				Time -= d
				LatestPath = NodeService.Compute(A, B, false, true)
				table.clear(newtable.PATH)
				for _, child in LatestPath do
					table.insert(newtable.PATH, child)
				end
			else
				COMPUTE_CONNEXION:Disconnect()
				PathContinuous["CONT-".. ID] = nil
				print("Continuous path was DISABLED and Deleted.")
			end		
		else
			COMPUTE_CONNEXION:Disconnect()
			PathContinuous["CONT-".. ID] = nil
		end
		
		
	end)
	
	return ID
end
--[[
	DEPRECATED UNTIL NEXT VERSION
]]
function NodeService.MultiContinuous(BlockList: {} , Time :number, WarningEnabled : boolean, display:boolean)
	local LatestPath = {}
	local ID = #PathContinuous + 1
	PathContinuous["CONT-"..ID] = {
		PATH = {},
		ENABLE = true
	}
	local newtable = PathContinuous["CONT-"..ID]
	if WarningEnabled then
		warn("[⚠ Node service warning] Multi-Computing Continuous may cause lag, it is recomanded to use this function for a set time amount but is allowed to be infinite (via setting Time to -1), this warning can be dissabled by setting WARNINGENABLED flag to false.")
	end
	
	local COMPUTE_CONNEXION :RBXScriptConnection
	COMPUTE_CONNEXION = game:GetService("RunService").Heartbeat:Connect(function(d)
		
		
		if Time > 0 then
			Time -= d
			if newtable.ENABLE == true then
				Time -= d
				LatestPath = NodeService:MultiCompute(BlockList, display, true)
				table.clear(newtable.PATH)
				for _, child in LatestPath do
					table.insert(newtable.PATH, child)
				end
				
			else
				COMPUTE_CONNEXION:Disconnect()
				PathContinuous["CONT-".. ID] = nil
				print("Continuous path was DISABLED and Deleted.")
			end
		elseif Time == -1 then
			
			--print("FOREVER MODE ON.")
			if newtable.ENABLE == true then
				
				LatestPath = NodeService:MultiCompute(BlockList, display, true)
				table.clear(newtable.PATH)
				for _, child in LatestPath do
					table.insert(newtable.PATH, child)
				end
			else
				COMPUTE_CONNEXION:Disconnect()
				PathContinuous["CONT-".. ID] = nil
				print("Continuous path was DISABLED and Deleted.")
			end	
		else
			COMPUTE_CONNEXION:Disconnect()
			PathContinuous["CONT-".. ID] = nil
		end

		table.clone(LatestPath)
	end)

	return ID
end

return NodeService
