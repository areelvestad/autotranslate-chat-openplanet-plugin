namespace ChatCapture {
	[Setting category="Capture" name="Chat scan interval (seconds)" min=0.05f max=3.0f]
	float S_PollIntervalSeconds = 0.15f;
	[Setting category="Capture" name="Include folded chat messages"]
	bool S_IncludeFoldedChat = false;

	CGamePlayground@ g_lastPlayground = null;
	uint64 g_lastPoll = 0;
	uint64 g_nextMessageId = 1;
	uint g_scannedLabels = 0;
	uint g_candidateCount = 0;
	string[] g_lastUnfolded;
	string[] g_lastFolded;
	bool g_unfoldedReady = false;
	bool g_foldedReady = false;
	string[] g_chatNames;
	string[] g_chatTexts;
	uint64[] g_chatIds;
	uint64[] g_chatObservedAt;

	void ClearStrings(array<string> &inout values) {
		while (values.Length > 0) values.RemoveAt(values.Length - 1);
	}

	void ClearUints(array<uint64> &inout values) {
		while (values.Length > 0) values.RemoveAt(values.Length - 1);
	}

	void ResetForPlayground(CGamePlayground@ playground) {
		@g_lastPlayground = playground;
		ClearStrings(g_lastUnfolded);
		ClearStrings(g_lastFolded);
		ClearStrings(g_chatNames);
		ClearStrings(g_chatTexts);
		ClearUints(g_chatIds);
		ClearUints(g_chatObservedAt);
		g_unfoldedReady = false;
		g_foldedReady = false;
		g_nextMessageId = 1;
		g_lastPoll = 0;
	}

	void ClearHistory() {
		ClearStrings(g_chatNames);
		ClearStrings(g_chatTexts);
		ClearUints(g_chatIds);
		ClearUints(g_chatObservedAt);
		g_candidateCount = 0;
		// Keep snapshots as baselines; don't replay visible rows after clearing.
	}

	array<string>@ ExtractPlayerChats(const string &in raw) {
		array<string>@ messages = array<string>();
		array<string>@ parts = raw.Split("$<");
		if (parts is null || parts.Length < 2) return messages;
		for (uint i = 1; i < parts.Length; i++) {
			string beforeTag = parts[i - 1];
			if (beforeTag.Length == 0 || beforeTag[beforeTag.Length - 1] != 91) continue;
			array<string>@ nameParts = parts[i].Split("$>]");
			if (nameParts is null || nameParts.Length < 2) continue;
			string playerName = Text::StripFormatCodes(nameParts[0]);
			array<string>@ messageParts = nameParts[1].Split("$z");
			string message = Text::StripFormatCodes(messageParts.Length > 0 ? messageParts[0] : nameParts[1]);
			if (playerName.Length > 0 && message.Length > 0) messages.InsertLast(playerName + "\n" + message);
		}
		return messages;
	}

	bool PairExists(const string &in pair) {
		array<string>@ fields = pair.Split("\n");
		if (fields.Length < 2) return false;
		for (uint i = 0; i < g_chatNames.Length; i++)
			if (g_chatNames[i] == fields[0] && g_chatTexts[i] == fields[1]) return true;
		return false;
	}

	void StoreIfNew(const string &in pair, const string &in source) {
		if (PairExists(pair)) return;
		array<string>@ fields = pair.Split("\n");
		if (fields.Length < 2) return;
		g_chatNames.InsertLast(fields[0]);
		g_chatTexts.InsertLast(fields[1]);
		g_chatIds.InsertLast(g_nextMessageId++);
		g_chatObservedAt.InsertLast(Time::Now);
		if (g_chatNames.Length > 28) {
			g_chatNames.RemoveAt(0);
			g_chatTexts.RemoveAt(0);
			g_chatIds.RemoveAt(0);
			g_chatObservedAt.RemoveAt(0);
		}
		g_candidateCount++;
		Translation::QueueChat(fields[0], fields[1]);
	}

	// Longest suffix of previous snapshot found contiguously in current snapshot.
	// Handles both a growing transcript and a rolling 28-row window.
	bool FindSnapshotAnchor(const array<string> &in previous, const array<string> &in current, int &out endIndex) {
		uint limit = previous.Length < current.Length ? previous.Length : current.Length;
		for (int count = int(limit); count > 0; count--) {
			for (uint start = 0; start + uint(count) <= current.Length; start++) {
				bool same = true;
				for (uint i = 0; i < uint(count); i++) {
					if (previous[previous.Length - uint(count) + i] != current[start + i]) { same = false; break; }
				}
				if (same) { endIndex = int(start + uint(count)); return true; }
			}
		}
		return false;
	}

	void CopySnapshot(array<string> &inout destination, const array<string> &in source) {
		ClearStrings(destination);
		for (uint i = 0; i < source.Length; i++) destination.InsertLast(source[i]);
	}

	void ProcessUnfolded(const array<string> &in current) {
		if (!g_unfoldedReady) {
			// First visible unfolded transcript seeds the plugin's 28-row history.
			for (uint i = 0; i < current.Length; i++) StoreIfNew(current[i], "unfolded");
			g_unfoldedReady = true;
		} else if (current.Length > 0 && !SameSnapshot(g_lastUnfolded, current)) {
			int anchorEnd = 0;
			if (FindSnapshotAnchor(g_lastUnfolded, current, anchorEnd)) {
				for (uint i = uint(anchorEnd); i < current.Length; i++) StoreIfNew(current[i], "unfolded");
			} else {
				// Rebased/reopened view: add only pairs absent from retained 28 rows.
				for (uint i = 0; i < current.Length; i++) StoreIfNew(current[i], "unfolded");
			}
		}
		CopySnapshot(g_lastUnfolded, current);
	}

	void ProcessFolded(const array<string> &in current) {
		if (!g_foldedReady) {
			for (uint i = 0; i < current.Length; i++) StoreIfNew(current[i], "folded");
			g_foldedReady = true;
		} else if (current.Length > 0 && !SameSnapshot(g_lastFolded, current)) {
			int anchorEnd = 0;
			if (FindSnapshotAnchor(g_lastFolded, current, anchorEnd)) {
				for (uint i = uint(anchorEnd); i < current.Length; i++) StoreIfNew(current[i], "folded");
			} else {
				for (uint i = 0; i < current.Length; i++) StoreIfNew(current[i], "folded");
			}
		}
		CopySnapshot(g_lastFolded, current);
	}

	bool SameSnapshot(const array<string> &in a, const array<string> &in b) {
		if (a.Length != b.Length) return false;
		for (uint i = 0; i < a.Length; i++) if (a[i] != b[i]) return false;
		return true;
	}

	CControlBase@ Child(CControlBase@ parent, uint index) {
		CControlContainer@ container = cast<CControlContainer>(parent);
		if (container is null || index >= container.Childs.Length) return null;
		return container.Childs[index];
	}

	string ReadChatLabel(CControlBase@ chatFrame, uint labelIndex) {
		CControlLabel@ label = cast<CControlLabel>(Child(chatFrame, labelIndex));
		return label is null ? "" : string(label.Label);
	}

	void Poll() {
		uint64 now = Time::Now;
		uint64 interval = uint64(S_PollIntervalSeconds * 1000.0f);
		if (g_lastPoll != 0 && now - g_lastPoll < interval) return;
		g_lastPoll = now;
		CGameCtnApp@ app = GetApp();
		if (app is null || app.CurrentPlayground is null) return;
		CGamePlayground@ playground = app.CurrentPlayground;
		if (playground !is g_lastPlayground) ResetForPlayground(playground);
		if (playground.Interface is null || playground.Interface.InterfaceRoot is null) return;

		CControlBase@ root = cast<CControlBase>(playground.Interface.InterfaceRoot);
		CControlBase@ frameChat = Child(Child(root, 2), 5);
		CControlBase@ folded = Child(frameChat, 0);
		CControlBase@ unfolded = Child(frameChat, 1);
		if (unfolded is null) return;
		string unfoldedRaw = ReadChatLabel(unfolded, 0);
		array<string>@ unfoldedMessages = ExtractPlayerChats(unfoldedRaw);
		g_scannedLabels = S_IncludeFoldedChat ? 2 : 1;
		ProcessUnfolded(unfoldedMessages);

		if (S_IncludeFoldedChat && folded !is null) {
			string foldedRaw = ReadChatLabel(folded, 3);
			array<string>@ foldedMessages = ExtractPlayerChats(foldedRaw);
			ProcessFolded(foldedMessages);
		}
	}

	uint GetScannedLabelCount() { return g_scannedLabels; }
	uint GetCandidateCount() { return g_candidateCount; }
	uint GetChatCount() { return g_chatNames.Length; }
	string GetChatName(uint index) { return g_chatNames[index]; }
	string GetChatText(uint index) { return g_chatTexts[index]; }
	string GetChatDisplay(uint index) {
		string line = g_chatNames[index] + ": " + g_chatTexts[index];
		string translated = Translation::GetTranslationFor(g_chatNames[index], g_chatTexts[index]);
		if (translated.Length == 0) return line;
		return line + "\nEN: " + translated;
	}
	uint64 GetChatId(uint index) { return g_chatIds[index]; }
	uint64 GetChatObservedAt(uint index) { return g_chatObservedAt[index]; }
}
