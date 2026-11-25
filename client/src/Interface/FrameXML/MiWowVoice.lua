-- MiWow: voz de grupo (fase 1, cliente web). Contraparte: MiWowVoice.cpp + web/servidor/voice.js. Ver docs/voz.md.
-- El audio lo lleva el navegador (WebRTC); este Lua solo pinta los botones y quien habla, y manda los clics:
--   VOICE_STATE <voz 0/1> <en sala 0/1> <mic 0/1> <altavoz 0/1> <error>   (voz = este cliente tiene voz: el web)
--   VOICE_SPEAK <nombre> 0/1                                               (el propio jugador o uno de su grupo)
--   VOICE_TOKEN <nonce>                                                    (para server.js; aqui no se usa)
-- Envia VOICE_MIC 0/1 y VOICE_SPEAKER 0/1. Sin voz (cliente de PC) no se ve nada.
--
-- Junto al minimapa, abajo a la izquierda:   ( mic )( altavoz )
-- Quien habla: el altavoz animado nativo de los marcos de jugador y de grupo (PlayerSpeakerFrame,
-- PartyMemberFrameNSpeakerFrame), los mismos que usaba el chat de voz de Blizzard.

MIWOW_STR_VOICE_MIC_ON = "Micrófono: |cff40ff40activado|r";
MIWOW_STR_VOICE_MIC_OFF = "Micrófono: |cffff4040desactivado|r";
MIWOW_STR_VOICE_SPEAKER_ON = "Altavoz: |cff40ff40activado|r";
MIWOW_STR_VOICE_SPEAKER_OFF = "Altavoz: |cffff4040silenciado|r";
MIWOW_STR_VOICE_CLICK = "Clic para cambiar";
MIWOW_STR_VOICE_GROUP_ONLY = "La voz es para tu grupo: únete a uno para hablar.";
MIWOW_STR_VOICE_TITLE = "Voz de grupo";
MIWOW_VOICE_ERRORS = {
	mic_denied = "El navegador no ha dado permiso para usar el micrófono.",
	mic_error = "No se ha podido usar el micrófono.",
	connect = "No se ha podido conectar a la voz.",
	load = "No se ha podido cargar la voz.",
};

MiWow_Voice = {
	available = false,
	inRoom = false,
	mic = false,
	speaker = true,
	err = "",
	speaking = {},   -- nombre -> true
};

local bar, micButton, speakerButton;

-- Boton redondo como los del minimapa: fondo oscuro, icono y aro
local function MiWow_VoiceButton(name, icon)
	local b = CreateFrame("Button", name, bar);
	b:SetSize(32, 32);
	b:SetFrameStrata("LOW");
	b:RegisterForClicks("LeftButtonUp");

	local bg = b:CreateTexture(nil, "BACKGROUND");
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background");
	bg:SetSize(20, 20);
	bg:SetPoint("TOPLEFT", 7, -5);

	b.icon = b:CreateTexture(nil, "ARTWORK");
	b.icon:SetTexture(icon);
	b.icon:SetSize(18, 18);
	b.icon:SetPoint("TOPLEFT", 8, -6);

	b.muted = b:CreateTexture(nil, "OVERLAY");
	b.muted:SetTexture("Interface\\Common\\VoiceChat-Muted");
	b.muted:SetAllPoints(b.icon);
	b.muted:Hide();

	local ring = b:CreateTexture(nil, "OVERLAY");
	ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder");
	ring:SetSize(53, 53);
	ring:SetPoint("TOPLEFT");

	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight");
	b:SetScript("OnLeave", function() GameTooltip:Hide(); end);
	return b;
end

local function MiWow_VoiceTooltip(self)
	local v = MiWow_Voice;
	GameTooltip:SetOwner(self, "ANCHOR_LEFT");
	GameTooltip:SetText(MIWOW_STR_VOICE_TITLE);
	if ( self == micButton ) then
		GameTooltip:AddLine(v.mic and MIWOW_STR_VOICE_MIC_ON or MIWOW_STR_VOICE_MIC_OFF);
	else
		GameTooltip:AddLine(v.speaker and MIWOW_STR_VOICE_SPEAKER_ON or MIWOW_STR_VOICE_SPEAKER_OFF);
	end
	if ( not v.inRoom ) then
		GameTooltip:AddLine(MIWOW_STR_VOICE_GROUP_ONLY, 1, 0.82, 0, true);
	else
		GameTooltip:AddLine(MIWOW_STR_VOICE_CLICK, 0.7, 0.7, 0.7);
	end
	GameTooltip:Show();
end

function MiWowVoice_Update()
	local v = MiWow_Voice;
	if ( not v.available ) then
		bar:Hide();
		return;
	end
	bar:Show();
	bar:SetAlpha(v.inRoom and 1 or 0.55);

	-- Microfono: apagado = gris con tachado; encendido = blanco; hablando = verde
	local me = UnitName("player");
	if ( v.mic and v.speaking[me] ) then
		micButton.icon:SetVertexColor(0.3, 1, 0.3);
	elseif ( v.mic ) then
		micButton.icon:SetVertexColor(1, 1, 1);
	else
		micButton.icon:SetVertexColor(0.5, 0.5, 0.5);
	end
	if ( v.mic ) then micButton.muted:Hide(); else micButton.muted:Show(); end

	speakerButton.icon:SetVertexColor(v.speaker and 1 or 0.5, v.speaker and 1 or 0.5, v.speaker and 1 or 0.5);
	if ( v.speaker ) then speakerButton.muted:Hide(); else speakerButton.muted:Show(); end
end

-- Altavoz animado de los marcos (mismo aspecto que el chat de voz nativo)
local function MiWow_SetFrameSpeaking(frame, on)
	if ( not frame ) then
		return;
	end
	if ( on ) then
		frame:Show();
		frame:SetAlpha(1);
		VoiceChat_Animate(frame, 1);
	else
		VoiceChat_Animate(frame, nil); -- tambien lo esconde
	end
end

function MiWowVoice_UpdateSpeakers()
	local speaking = MiWow_Voice.speaking;
	for i = 1, MAX_PARTY_MEMBERS do
		local name = UnitName("party"..i);
		MiWow_SetFrameSpeaking(_G["PartyMemberFrame"..i.."SpeakerFrame"], name and speaking[name]);
	end
	if ( PlayerSpeakerFrame ) then
		if ( speaking[UnitName("player")] ) then
			PlayerFrame_UpdateVoiceStatus(true);
		elseif ( PlayerSpeakerFrame:IsShown() ) then
			PlayerFrame_UpdateVoiceStatus(false);
		end
	end
end

local function MiWow_ToggleMic()
	local v = MiWow_Voice;
	if ( not v.available ) then
		return;
	end
	if ( not v.inRoom ) then
		UIErrorsFrame:AddMessage(MIWOW_STR_VOICE_GROUP_ONLY, 1, 0.82, 0, 1.0);
		return;
	end
	PlaySound(v.mic and "igMainMenuOptionCheckBoxOff" or "igMainMenuOptionCheckBoxOn");
	MiWow_Send("VOICE_MIC", v.mic and 0 or 1);
end

local function MiWow_ToggleSpeaker()
	local v = MiWow_Voice;
	if ( not v.available ) then
		return;
	end
	PlaySound(v.speaker and "igMainMenuOptionCheckBoxOff" or "igMainMenuOptionCheckBoxOn");
	MiWow_Send("VOICE_SPEAKER", v.speaker and 0 or 1);
end

local function MiWow_CreateFrame()
	bar = CreateFrame("Frame", "MiWowVoiceBar", Minimap);
	bar:SetSize(68, 32);
	bar:SetPoint("TOPRIGHT", Minimap, "BOTTOMLEFT", 6, 18);
	bar:Hide();

	micButton = MiWow_VoiceButton("MiWowVoiceMicButton", "Interface\\TouchUI\\MiWow\\u_mic");
	micButton:SetPoint("LEFT", bar, "LEFT", 0, 0);
	micButton:SetScript("OnClick", MiWow_ToggleMic);
	micButton:SetScript("OnEnter", MiWow_VoiceTooltip);

	speakerButton = MiWow_VoiceButton("MiWowVoiceSpeakerButton", "Interface\\Common\\VoiceChat-Speaker");
	speakerButton:SetPoint("LEFT", micButton, "RIGHT", 2, 0);
	speakerButton:SetScript("OnClick", MiWow_ToggleSpeaker);
	speakerButton:SetScript("OnEnter", MiWow_VoiceTooltip);

	bar:RegisterEvent("PARTY_MEMBERS_CHANGED");
	bar:SetScript("OnEvent", function()
		-- Los que ya no estan en el grupo dejan de contar
		local still = {};
		still[UnitName("player")] = true;
		for i = 1, MAX_PARTY_MEMBERS do
			local name = UnitName("party"..i);
			if ( name ) then
				still[name] = true;
			end
		end
		for name in pairs(MiWow_Voice.speaking) do
			if ( not still[name] ) then
				MiWow_Voice.speaking[name] = nil;
			end
		end
		MiWowVoice_UpdateSpeakers();
	end);
end

-- El marco de grupo nativo esconde su altavoz al actualizarse (UnitIsTalking es siempre falso: no hay voz nativa)
hooksecurefunc("PartyMemberFrame_UpdateVoiceStatus", function(self)
	local id = self and self:GetID();
	local name = id and UnitName("party"..id);
	if ( name and MiWow_Voice.speaking[name] ) then
		MiWow_SetFrameSpeaking(_G["PartyMemberFrame"..id.."SpeakerFrame"], true);
	end
end);

-- Protocolo -------------------------------------------------------------------------------------

-- VOICE_STATE <voz> <en sala> <mic> <altavoz> <error>
MiWow_RegisterHandler("VOICE_STATE", function(fields)
	local v = MiWow_Voice;
	v.available = fields[1] == "1";
	v.inRoom = fields[2] == "1";
	v.mic = fields[3] == "1";
	v.speaker = fields[4] == "1";
	local err = fields[5] or "";
	if ( err ~= "" and err ~= v.err and MIWOW_VOICE_ERRORS[err] ) then
		UIErrorsFrame:AddMessage(MIWOW_VOICE_ERRORS[err], 1, 0.1, 0.1, 1.0);
	end
	v.err = err;
	if ( not v.inRoom or not v.available ) then
		wipe(v.speaking);
		MiWowVoice_UpdateSpeakers();
	end
	MiWowVoice_Update();
end);

-- VOICE_SPEAK <nombre> 0/1
MiWow_RegisterHandler("VOICE_SPEAK", function(fields)
	local name = fields[1];
	if ( not name or name == "" ) then
		return;
	end
	MiWow_Voice.speaking[name] = (fields[2] == "1") or nil;
	MiWowVoice_UpdateSpeakers();
	MiWowVoice_Update();
end);

MiWow_RegisterHandler("VOICE_TOKEN", function() end);

-- Al reconectar el protocolo (/reload) el servidor vuelve a mandar VOICE_STATE
MiWow_RegisterListener("CONNECTED", function()
	MiWow_Voice.available = false;
	wipe(MiWow_Voice.speaking);
	MiWowVoice_UpdateSpeakers();
	MiWowVoice_Update();
end);

SLASH_MIWOWVOICE1 = "/voz";
SlashCmdList["MIWOWVOICE"] = function(msg)
	msg = strlower(strtrim(msg or ""));
	if ( msg == "altavoz" or msg == "speaker" ) then
		MiWow_ToggleSpeaker();
	else
		MiWow_ToggleMic();
	end
end;

MiWow_CreateFrame();
