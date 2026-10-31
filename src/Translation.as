namespace Translation {
	[Setting category="LibreTranslate" name="API base URL"]
	string S_BaseUrl = "";

	[Setting category="LibreTranslate" name="Translation endpoint"]
	string S_Endpoint = "/translate";

	[Setting category="LibreTranslate" name="HTTP method"]
	string S_Method = "POST";

	[Setting category="LibreTranslate" name="Source language"]
	string S_SourceLanguage = "auto";

	[Setting category="LibreTranslate" name="Target language"]
	string S_TargetLanguage = "en";

	[Setting category="LibreTranslate" name="API key"]
	string S_ApiKey = "";

	string[] g_names;
	string[] g_originals;
	string[] g_translations;
	bool[] g_isEnglish;
	int[] g_pending;
	string g_status = "Idle";
	bool g_requestInFlight = false;
	uint g_clearGeneration = 0;

	void QueueChat(const string &in playerName, const string &in message) {
		// Chat labels are snapshots, so capture can observe the same row again
		// when the unfolded history refreshes. Never enqueue a pair twice.
		for (int i = int(g_names.Length) - 1; i >= 0; i--) {
			if (g_names[uint(i)] == playerName && g_originals[uint(i)] == message) return;
		}
		g_names.InsertLast(playerName);
		g_originals.InsertLast(message);
		g_translations.InsertLast("Translating...");
		g_isEnglish.InsertLast(false);
		g_pending.InsertLast(int(g_names.Length - 1));
		PruneHistory();
	}

	void PruneHistory() {
		if (g_requestInFlight) return;
		while (g_names.Length > 256) {
			g_names.RemoveAt(0);
			g_originals.RemoveAt(0);
			g_translations.RemoveAt(0);
			g_isEnglish.RemoveAt(0);
			for (int i = int(g_pending.Length) - 1; i >= 0; i--) {
				if (g_pending[uint(i)] == 0) g_pending.RemoveAt(uint(i));
				else g_pending[uint(i)]--;
			}
		}
	}

	void ClearHistory() {
		g_clearGeneration++;
		while (g_names.Length > 0) g_names.RemoveAt(g_names.Length - 1);
		while (g_originals.Length > 0) g_originals.RemoveAt(g_originals.Length - 1);
		while (g_translations.Length > 0) g_translations.RemoveAt(g_translations.Length - 1);
		while (g_isEnglish.Length > 0) g_isEnglish.RemoveAt(g_isEnglish.Length - 1);
		while (g_pending.Length > 0) g_pending.RemoveAt(g_pending.Length - 1);
		if (!g_requestInFlight) g_status = "Idle";
	}

	bool HasPending() { return g_pending.Length > 0; }
	void TranslateNext() {
		if (g_pending.Length == 0) return;
		int index = g_pending[0];
		g_pending.RemoveAt(0);
		if (S_BaseUrl.Length == 0 || S_Endpoint.Length == 0) {
			g_translations[uint(index)] = "Missing API base URL or endpoint.";
			return;
		}
		if (S_Method != "POST") {
			g_translations[uint(index)] = "LibreTranslate requires HTTP POST.";
			return;
		}
		uint generation = g_clearGeneration;

		Json::Value@ body = Json::Object();
		body["q"] = g_originals[uint(index)];
		body["source"] = S_SourceLanguage;
		body["target"] = S_TargetLanguage;
		body["format"] = "text";
		if (S_ApiKey.Length > 0) body["api_key"] = S_ApiKey;
		string requestBody = Json::Write(body);
		string url = S_BaseUrl + S_Endpoint;
		// HttpPost starts the request. Poll completion so unreachable servers
		// produce a useful timeout status instead of leaving the UI stuck.
		Net::HttpRequest@ request = Net::HttpPost(url, requestBody, "application/json; charset=utf-8");
		g_requestInFlight = true;
		g_status = "Translating...";
		uint64 startedAt = Time::Now;
		while (!request.Finished() && Time::Now - startedAt < 15000) sleep(50);
		g_requestInFlight = false;
		if (generation != g_clearGeneration) {
			g_status = "Idle";
			PruneHistory();
			return;
		}
		if (!request.Finished()) {
			request.Cancel();
			g_status = "Idle";
			g_translations[uint(index)] = "Request timed out. Check LibreTranslate URL/server.";
			print("[ChatCapture] Translation request timed out. URL=" + url);
			PruneHistory();
			return;
		}

		if (request.Error().Length > 0 || request.ResponseCode() != 200) {
			string detail = request.Error();
			if (detail.Length == 0) detail = "HTTP " + Text::Format("%d", int(request.ResponseCode()));
			g_translations[uint(index)] = "Translation failed: " + detail;
			g_status = "Idle";
			print("[ChatCapture] " + g_translations[uint(index)] + " URL=" + url + " response=" + request.String());
			PruneHistory();
			return;
		}

		Json::Value@ response = request.Json();
		if (response is null || !response.HasKey("translatedText")) {
			g_translations[uint(index)] = "Translation failed: invalid response.";
			g_status = "Idle";
			print("[ChatCapture] " + g_status + " " + request.String());
			PruneHistory();
			return;
		}

		string detectedLanguage = "";
		if (response.HasKey("detectedLanguage")) {
			Json::Value@ detected = response["detectedLanguage"];
			if (detected !is null && detected.HasKey("language")) detectedLanguage = string(detected["language"]);
		}
		array<string>@ languageParts = detectedLanguage.Split("-");
		g_isEnglish[uint(index)] = languageParts.Length > 0 && languageParts[0] == "en";
		g_translations[uint(index)] = string(response["translatedText"]);
		g_status = "Idle";
		PruneHistory();
	}

	uint GetCount() { return g_names.Length > 30 ? 30 : g_names.Length; }
	string GetDisplay(uint index) {
		if (g_names.Length > 30) index += g_names.Length - 30;
		if (g_isEnglish[index]) return g_names[index] + ": " + g_originals[index];
		return g_names[index] + ": " + g_originals[index] + "\nEN: " + g_translations[index];
	}
	string GetStatus() { return g_status; }
	string GetTranslationFor(const string &in playerName, const string &in original) {
		int first = int(g_names.Length) - 256;
		if (first < 0) first = 0;
		for (int i = int(g_names.Length) - 1; i >= first; i--) {
			if (g_names[uint(i)] != playerName || g_originals[uint(i)] != original) continue;
			if (g_isEnglish[uint(i)]) return "";
			return g_translations[uint(i)];
		}
		return "Translating...";
	}
}
