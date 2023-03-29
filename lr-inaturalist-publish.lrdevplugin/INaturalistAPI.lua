require("strict")

local logger = import("LrLogger")("lr-inaturalist-publish")
local LrHttp = import("LrHttp")
local LrPathUtils = import("LrPathUtils")
local LrStringUtils = import("LrStringUtils")

local JSON = require("JSON")

INaturalistAPI = {
	clientId = "abue3CpJkLe1adPWFNFzrCj_riap_diH0bpGGq2HYIE",
	oauthRedirect = "lightroom://net.rcloran.lr-inaturalist-publish/authorization-redirect",
	apiBase = "https://api.inaturalist.org/v1/",
}

-- Constructor -- an instnance of the API stores the access token locally, and
-- handles obtaining JWT (tokens for the new API), which are short-lived, as
-- needed.
function INaturalistAPI:new(accessToken)
	local o = {}
	setmetatable(o, { __index = INaturalistAPI })
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

local function maybeError(headers)
	if headers.error then
		error(headers.error.name)
	elseif headers.status ~= 200 then
		local msg = string.format("API error: %s", headers.status)
		error(msg)
	end
end

function INaturalistAPI:apiGet(path)
	logger:trace("apiGet()", path)
	local url = INaturalistAPI.apiBase .. path
	local headers = self:headers()

	local data, headers = LrHttp.get(url, headers)

	maybeError(headers)
	return JSON:decode(data)
end

function INaturalistAPI:apiPost(path, content, method)
	logger:trace("apiPost()", path, method)
	local url = INaturalistAPI.apiBase .. path
	local headers = self:headers()
	content = JSON:encode(content)

	local data, headers = LrHttp.post(url, content, headers, method)

	maybeError(headers)
	return JSON:decode(data)
end

function INaturalistAPI:apiPostMultipart(path, content)
	logger:trace("apiPostMultipart()", path)
	local url = INaturalistAPI.apiBase .. path
	local headers = self:headers()

	local data, headers = LrHttp.postMultipart(url, content, headers)

	maybeError(headers)
	return JSON:decode(data)
end

function INaturalistAPI:apiDelete(path)
	logger:trace("apiDelete()", path)
	return self:apiPost(path, "", "DELETE")
end

function INaturalistAPI:apiPut(path, content)
	logger:trace("apiPut()", path)
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
	local data, headers = LrHttp.get(url, headers)
	if headers.error then
		error(headers.error.name)
	elseif headers.status ~= 200 then
		msg = string.format("API error: %s", headers.status)
		error(msg)
	end
	data = JSON:decode(data)
	self.api_token = data.api_token
	return data.api_token
end

-- The convenient way of handling the JWT; a thin caching layer over
-- getAPIToken.
function INaturalistAPI:jwt()
	logger:trace("jwt()")
	if self.api_token then
		-- TODO: Handle expired tokens
		return self.api_token
	end
	logger:trace("  getting a new token")
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
	logger:trace("createObservationPhoto()")
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
-- POST /observations -- Observation Create
function INaturalistAPI:createObservation(observation)
	logger:trace("createObservation()", observation)
	return self:apiPost("observations", observation)
end
-- deleteObservation -- DELETE /observations/{id} -- Observation Delete
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
	logger:trace("getUser()")
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
	logger:trace("createPhoto()")
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
