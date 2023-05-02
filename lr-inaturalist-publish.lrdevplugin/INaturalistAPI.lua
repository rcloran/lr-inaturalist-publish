local logger = import("LrLogger")("lr-inaturalist-publish")
local LrHttp = import("LrHttp")
local LrPasswords = import("LrPasswords")
local LrPathUtils = import("LrPathUtils")
local LrStringUtils = import("LrStringUtils")
local LrTasks = import("LrTasks")

local JSON = require("JSON")

local INaturalistAPI = {
	clientId = "abue3CpJkLe1adPWFNFzrCj_riap_diH0bpGGq2HYIE",
	oauthRedirect = "lightroom://net.rcloran.lr-inaturalist-publish/authorization-redirect",
	apiBase = "https://api.inaturalist.org/v1/",
}

-- Constructor -- an instance of the API stores the access token locally, and
-- handles obtaining JWT (tokens for the new API), which are short-lived, as
-- needed.
function INaturalistAPI:new(login, accessToken)
	local o = {}
	setmetatable(o, { __index = self })
	if login and not accessToken then
		accessToken = LrPasswords.retrieve(login)
	end
	o.accessToken = accessToken
	return o
end

function INaturalistAPI.urlencode(s)
	-- RFC3986 2.3
	s = string.gsub(s, "([^%w ._~-])", function(c)
		return string.format("%%%02X", string.byte(c))
	end)
	s = string.gsub(s, " ", "+")
	return s
end

function INaturalistAPI.formEncode(t)
	local fields = {}
	for k, v in pairs(t) do
		local field = string.format("%s=%s", INaturalistAPI.urlencode(k), INaturalistAPI.urlencode(v))
		table.insert(fields, field)
	end
	return table.concat(fields, "&")
end

local retryable = {
	[503] = true,
	["networkConnectionLost"] = true,
}

local function req(f, ...)
	-- Make an HTTP request for an API call, normalizing errors and response
	-- types and handling retries
	local err = nil
	for i = 1, 3 do
		local data, headers = f(...)
		if headers.error then
			err = { code = headers.error.errorCode, message = headers.error.name }
		elseif headers.status ~= 200 then
			err = { code = headers.status, message = headers.statusDes }
		else
			return JSON:decode(data)
		end

		if not retryable[err.code] then
			logger:debugf("Un-retryable error: %s", err.code)
			error(err)
		elseif i ~= 3 then
			logger:debugf("Retryable error: %s", err.code)
			LrTasks.sleep(math.random(i * 1000) / 1000) -- Back off up to i seconds
		end
	end

	logger:debugf("Exceeded retries, throwing error: %s", err.code)
	error(err)
end

local function shallowCopy(table)
	local r = {}
	for k, v in pairs(table) do
		r[k] = v
	end
	return r
end

function INaturalistAPI:apiGet(path)
	logger:tracef("apiGet(%s)", path)
	local url = INaturalistAPI.apiBase .. path
	local headers = self:headers()

	return req(LrHttp.get, url, headers)
end

function INaturalistAPI:apiPost(path, content, method, content_type)
	logger:tracef("apiPost(%s, ..., %s)", path, method)
	local url = INaturalistAPI.apiBase .. path
	local headers = self:headers()
	if not content_type then
		if content then
			content_type = "application/json"
		else
			content_type = "skip"
		end
	end
	table.insert(headers, { field = "Content-Type", value = content_type })

	if content then
		content = JSON:encode(content)
	else
		content = ""
	end

	return req(LrHttp.post, url, content, headers, method)
end

function INaturalistAPI:apiPostMultipart(path, content)
	logger:tracef("apiPostMultipart(%s)", path)
	local url = INaturalistAPI.apiBase .. path
	local headers = self:headers()

	return req(LrHttp.postMultipart, url, content, headers)
end

function INaturalistAPI:apiDelete(path)
	logger:tracef("apiDelete(%s)", path)
	return self:apiPost(path, nil, "DELETE")
end

function INaturalistAPI:apiPut(path, content)
	logger:tracef("apiPut(%s)", path)
	return self:apiPost(path, content, "PUT")
end

-- Take a long-lived bearer token that works for the old API and return a
-- short-lived JWT (JSON Web Token) that works for the new API
function INaturalistAPI:getAPIToken()
	logger:trace("getAPIToken()")
	local url = "https://www.inaturalist.org/users/api_token"
	local headers = {
		{ field = "Accept", value = "application/json" },
		{ field = "Authorization", value = "Bearer " .. self.accessToken },
	}
	local data = req(LrHttp.get, url, headers)
	self.api_token = data.api_token
	return data.api_token
end

-- The convenient way of handling the JWT; a thin caching layer over
-- getAPIToken.
function INaturalistAPI:jwt()
	if self.api_token then
		-- TODO: Handle expired tokens
		return self.api_token
	end
	logger:debug("Getting a new token")
	return self:getAPIToken()
end

function INaturalistAPI:headers()
	local jwt = self:jwt()
	return {
		{ field = "Accept", value = "application/json" },
		{ field = "Authorization", value = string.format("JWT %s", jwt) },
	}
end

-- https://api.inaturalist.org/v1/docs/
-- createAnnotation -- POST /annotations
-- deleteAnnotation -- DELETE /annotations/{id}
-- createAnnotationVote -- POST /votes/vote/annotation/{id}
-- deleteAnnotationVote -- DELETE /votes/vote/annotation/{id}
--
-- createComment -- POST /comments
-- deleteComment -- DELETE /comments/{id}
-- updateComment -- PUT /comments/{id}
--
-- listControlledTerms -- GET /controlled_terms
-- listControlledTermsForTaxon -- GET /controlled_terms/for_taxon
--
-- createFlag -- POST /flags
-- deleteFlag -- DELETE /flags/{id}
-- updateFlag -- PUT /flags/{id}
--
-- listIdentifications -- GET /identifications
-- createIdentification -- POST /identifications
-- deleteIdentification -- DELETE /identifications/{id}
-- updateIdentification -- PUT /identifications/{id}
-- getIdentification -- GET /identifications/{id}
-- listIdentificationCategories -- GET /identifications/categories
-- listIdentificationSpeciesCounts -- GET /identifications/species_counts
-- listIdentificationIdentifiers -- GET /identifications/identifiers
-- listIdentificationObservers -- GET /identifications/observers
-- listIdentificationRecentTaxa -- GET /identifications/recent_taxa
-- listIdentificationSimilarSpecies -- GET /identifications/similar_species
--
-- listMessages -- GET /messages
-- createMessage -- POST /messages
-- deleteMessage -- DELETE /messages/{id}
-- getMessage -- GET /messages/{id}
-- getMessagesUnread -- GET /messages/unread
--
-- createObservationFieldValue -- POST /observation_field_values
-- deleteObservationFieldValue -- DELETE /observation_field_values/{id}
-- updateObservationFieldValues -- PUT /observation_field_values/{id}
--
-- POST /observation_photos
function INaturalistAPI:createObservationPhoto(filePath, observation_id)
	local content = {
		{
			name = "observation_photo[observation_id]",
			value = observation_id,
		},
		{
			name = "file",
			filePath = filePath,
			fileName = LrPathUtils.leafName(filePath),
			contentType = "application/octet-stream",
		},
	}

	return self:apiPostMultipart("observation_photos", content)
end
-- deleteObservationPhoto -- DELETE /observation_photos/{id}
-- updateObservationPhoto -- PUT /observation_photos/{id}
--
-- listObservations -- GET /observations -- Observation Search
function INaturalistAPI:listObservations(search)
	local qs = INaturalistAPI.formEncode(search)

	local observation = self:apiGet("observations?" .. qs)
	return observation.results
end
-- Like listObservations, but deals with pagination and compiles all results
-- into one table.
-- Overrides per_page, order_by, order, id_above, id_below in the search;
-- results are always ordered descending by id.
function INaturalistAPI:listObservationsWithPagination(search, progress, limit)
	local results, resultsRemain = {}, true

	search = shallowCopy(search)
	search.per_page = 100
	search.order_by = "id"
	search.order = "desc"
	search.id_above = nil
	search.id_below = nil

	while resultsRemain and (not limit or #results < limit) do
		if progress:isCanceled() then
			error({ code = "canceled", message = "Canceled by user" })
		end

		local qs = INaturalistAPI.formEncode(search)
		local newResults = self:apiGet("observations?" .. qs)
		-- total_results keeps changing on us because id_below.
		local totalResults = newResults.total_results + #results
		for i = 1, #newResults.results do
			results[#results + 1] = newResults.results[i]
		end
		resultsRemain = #newResults.results >= newResults.per_page

		if progress then
			progress:setPortionComplete(#results / totalResults)
			progress:setCaption("Downloading observations (" .. #results .. "/" .. totalResults .. ")")
		end

		if #newResults.results > 0 then
			search.id_below = newResults.results[#newResults.results].id
		end
	end

	if progress then
		progress:done()
	end
	return results
end
-- POST /observations -- Observation Create
function INaturalistAPI:createObservation(observation)
	return self:apiPost("observations", observation)
end
-- DELETE /observations/{id} -- Observation Delete
function INaturalistAPI:deleteObservation(id)
	assert(string.len(id) > 0)

	return self:apiDelete("observations/" .. id)
end
-- getObservation -- GET /observations/{id} -- Observation Details
-- updateObservation -- PUT /observations/{id} -- Observation Update
-- createObservationFave -- POST /observations/{id}/fave -- Observations Fave
-- deleteObservationFave -- DELETE /observations/{id}/unfave -- Observations Unfave
-- createObservationReview -- POST /observations/{id}/review -- Observations Review
-- deleteObservationReview -- POST /observations/{id}/unreview -- Observations Unreview
-- getObservationSubscriptions -- GET /observations/{id}/subscriptions -- Observation Subscriptions
-- deleteObservationQualityMetric -- DELETE /observations/{id}/quality/{metric} -- Quality Metric Delete
-- updateObservationQualityMetric -- POST /observations/{id}/quality/{metric} -- Quality Metric Set
-- getObservationTaxonSummary -- GET /observations/{id}/taxon_summary -- Observation Taxon Summary
-- createObservationSubscription -- POST /subscriptions/observation/{id}/subscribe -- Observation Subscribe
-- createObservationVote -- POST /votes/vote/observation/{id} -- Observation Vote
-- deleteObservationVote -- DELETE /votes/unvote/observation/{id} -- Observation Unvote
-- listDeletedObservations -- GET /observations/deleted -- Observations Deleted
-- getObservationHistogram -- GET /observations/histogram -- Observation Histogram
-- listObservationIdentifiers -- GET /observations/identifiers -- Observation Identifiers
-- listObservationObservers -- GET /observations/observers -- Observation Observers
-- listObservationPopularFieldValues -- GET /observations/popular_field_values -- Observation Popular Field Values
-- listObservationSpeciesCounts -- GET /observations/species_counts -- Observation Species Counts
-- listObservationUserUpdates -- GET /observations/updates -- Observation User Updates
-- updateObservationUpdates -- PUT /observations/{id}/viewed_updates -- Observation Field Value Update
--
-- listPlaces -- GET /places/autocomplete
-- listPlacesNearby -- GET /places/nearby
-- getPlace -- GET /places/{id}
--
-- listPosts -- GET /posts
-- createPost -- POST /posts
-- deletePost -- DELETE /posts/{id}
-- updatePost -- PUT /posts/{id}
-- listPostsForUser -- GET /posts/for_user
--
-- createProjectObservation -- POST /project_observations
-- deleteProjectObservation -- DELETE /project_observations/{id}
-- updateProjectObservation -- PUT /project_observations/{id}
--
-- listProjects -- GET /projects -- Project Search
-- getProject -- GET /projects/{id} -- Project Details
-- createProjectMembership -- POST /projects/{id}/join -- Projects Join
-- deleteProjectMembership -- DELETE /projects/{id}/leave -- Projects Leave
-- listProjectMembers -- GET /projects/{id}/members -- Project Members
-- getProjectMembership -- GET /projects/{id}/membership -- Membership of current user
-- DEPRECATED getProjectSubscriptions -- GET /projects/{id}/subscriptions -- Project Subscriptions
-- createProject -- POST /projects/{id}/add -- Project Add
-- deleteProject -- DELETE /projects/{id}/remove -- Project Add
-- listProjectNames -- GET /projects/autocomplete -- Project Autocomplete
-- (DEPRECATED?) createProjectSubscription -- POST /subscriptions/project/{id}/subscribe -- Project Subscribe
--
-- search -- GET /search
--
-- listTaxa -- GET /taxa
-- listTaxaNames -- GET /taxa/autocomplete
-- getTaxon -- GET /taxa/{id}
--
--
-- GET /users/{id} -- User Details
-- GET /users/me -- Users Me
-- Get user details by ID. Gets the currently logged in user if id is nil.
function INaturalistAPI:getUser(id)
	if id == nil then
		id = "me"
	elseif type(id) == "number" then
		id = LrStringUtils.numberToString(id)
	end
	assert(string.len(id) > 0)

	local user = self:apiGet("users/" .. id)
	return user.results[1]
end
-- updateUser -- PUT /users/{id}-- User Update
-- listUserProjects -- GET /users/{id}/projects -- User Projects
-- listUserNames -- GET /users/autocomplete -- User Autocomplete
-- deleteUserMute -- DELETE /users/{id}/mute -- Unmute a User
-- createUserMute -- POST /users/{id}/mute -- Mute a User
-- updateUserSession -- PUT /users/update_session -- User Update Session
--
-- The following 4 are available as .png ("tile") and .grid.json ("UTFGrid")
-- getTileColoredHeatmap -- GET /colored_heatmap/{zoom}/{x}/{y}.png -- Colored Heatmap Tiles
-- getTileGrid -- GET /grid/{zoom}/{x}/{y}.png -- Grid Tiles
-- getTileHeatmap -- GET /heatmap/{zoom}/{x}/{y}.png -- Heatmap Tiles
-- getTilePoints -- GET /points/{zoom}/{x}/{y}.png -- Points Tiles
--
-- getTilePlace -- GET /places/{place_id}/{zoom}/{x}/{y}.png -- Place Tiles
-- getTileTaxonPlace -- GET /taxon_places/{taxon_id}/{zoom}/{x}/{y}.png -- Taxon Place Tiles
-- getTileTaxonRange -- GET /taxon_ranges/{taxon_id}/{zoom}/{x}/{y}.png -- Taxon Range Tiles
--
-- createPhoto -- POST /photos
function INaturalistAPI:createPhoto(filePath)
	local content = {
		{
			name = "file",
			filePath = filePath,
			fileName = LrPathUtils.leafName(filePath),
			contentType = "application/octet-stream",
		},
	}

	return self:apiPostMultipart("photos", content)
end

-- Old (Rails-based) API!
function INaturalistAPI:deletePhoto(id)
	logger:tracef("deletePhoto(%s)", id)
	assert(string.len(id) > 0)
	local url = "https://www.inaturalist.org/photos/" .. id
	local headers = {
		{ field = "Accept", value = "application/json" },
		{ field = "Authorization", value = self:jwt() },
	}
	return req(LrHttp.post, url, "", headers, "DELETE")
end

return INaturalistAPI
