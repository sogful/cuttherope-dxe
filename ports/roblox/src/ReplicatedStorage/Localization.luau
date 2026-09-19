local data = require(script.Parent.LocaleData)
local session = require(script.Parent.SessionState)
local Localization = {}
Localization.codes = { "en", "ru", "de", "fr", "es", "it", "nl", "pt_br", "ko", "ja", "zh", "zh_tw" }
-- LanguageHelper.GetLanguageDisplayName intentionally uses English names.
Localization.names = { "English", "Russian", "German", "French", "Spanish", "Italian", "Dutch", "Portuguese", "Korean", "Japanese", "Chinese", "Tr. Chinese" }
function Localization.set(code)
	assert(data[code], "Unsupported DX locale")
	session.locale = code
end
function Localization.get(key)
	return (data[session.locale] or data.en)[key] or data.en[key] or key
end
local keys = {}
for key, value in pairs(data.en) do keys[value] = key end
function Localization.text(english)
	local key = keys[english]
	return key and Localization.get(key) or english
end
return Localization
