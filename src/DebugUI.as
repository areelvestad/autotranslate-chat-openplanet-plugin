namespace DebugUI {
	[Setting category="Display" name="Opacity when not hovered" min=0.05f max=1.0f]
	float S_IdleOpacity = 0.25f;
	[Setting category="Display" name="Opacity when hovered" min=0.2f max=1.0f]
	float S_HoverOpacity = 1.0f;
	[Setting category="Display" name="Window background opacity" min=0.1f max=1.0f]
	float S_BackgroundOpacity = 0.85f;
	[Setting category="Display" name="Name column width (px)" min=40.0f max=180.0f]
	float S_NameColumnWidth = 82.0f;
	[Setting category="Display" name="Original text opacity" min=0.2f max=1.0f]
	float S_OriginalTextOpacity = 0.62f;
	[Setting category="Display" name="Message spacing (px)" min=0.0f max=12.0f]
	float S_MessageSpacing = 2.0f;
	[Setting category="Display" name="Message line opacity" min=0.0f max=1.0f]
	float S_MessageLineOpacity = 1.0f;

	bool g_windowHovered = false;
	bool g_showChat = true;
	float g_expandedWindowHeight = 500.0f;
	UI::Font@ g_italicFont = null;
	bool g_triedItalicFont = false;

	void Initialize() {
		if (g_triedItalicFont) return;
		@g_italicFont = UI::LoadFont("C:/Windows/Fonts/ariali.ttf", 16.0f);
		g_triedItalicFont = true;
	}

	void RenderWindow() {
		// Apply whole-window opacity. Hover state from previous frame avoids
		// changing style after Begin has already drawn the window background.
		vec4 windowBg = UI::GetStyleColor(UI::Col::WindowBg);
		windowBg.w *= S_BackgroundOpacity;
		UI::PushStyleColor(UI::Col::WindowBg, windowBg);
		UI::PushStyleVar(UI::StyleVar::Alpha, g_windowHovered ? S_HoverOpacity : S_IdleOpacity);
		bool open = UI::Begin("Autotranslate Chat");
		vec2 mousePos = UI::GetMousePos();
		vec2 windowPos = UI::GetWindowPos();
		vec2 windowSize = UI::GetWindowSize();
		if (g_showChat) g_expandedWindowHeight = windowSize.y;
		g_windowHovered = mousePos.x >= windowPos.x && mousePos.x <= windowPos.x + windowSize.x
			&& mousePos.y >= windowPos.y && mousePos.y <= windowPos.y + windowSize.y;
		if (!open) {
			UI::End();
			UI::PopStyleVar();
			UI::PopStyleColor();
			return;
		}
		if (UI::Button(g_showChat ? "Collapse chat" : "Show translated chat")) {
			g_showChat = !g_showChat;
			UI::SetWindowSize(vec2(windowSize.x, g_showChat ? g_expandedWindowHeight : 86.0f), UI::Cond::Always);
		}
		UI::SameLine();
		UI::SetCursorPosX(UI::GetWindowContentRegionMax().x - 82.0f);
		if (UI::Button("Clear chat")) {
			ChatCapture::ClearHistory();
			Translation::ClearHistory();
		}
		if (g_showChat) {
			UI::Separator();
			bool showMessages = UI::BeginChild("translated-chat", vec2(0, 0), UI::ChildFlags::Border);
			if (showMessages) {
			// Follow new rows only while already at the bottom. Manual scrollback
			// remains usable when the viewer has scrolled up.
			bool followBottom = UI::GetScrollY() >= UI::GetScrollMaxY() - 2.0f;
			UI::PushStyleColor(UI::Col::TableBorderStrong, vec4(1.0f, 1.0f, 1.0f, S_MessageLineOpacity));
			UI::PushStyleColor(UI::Col::TableBorderLight, vec4(1.0f, 1.0f, 1.0f, S_MessageLineOpacity));
			UI::PushStyleVar(UI::StyleVar::CellPadding, vec2(4.0f, S_MessageSpacing / 2.0f));
			if (UI::BeginTable("chat-columns", 2, UI::TableFlags::BordersInnerH)) {
				UI::TableSetupColumn("Name", UI::TableColumnFlags::WidthFixed, S_NameColumnWidth);
				UI::TableSetupColumn("Message", UI::TableColumnFlags::WidthStretch);
				for (uint i = 0; i < ChatCapture::GetChatCount(); i++) {
					UI::TableNextRow();
					UI::TableSetColumnIndex(0);
					UI::TextWrapped(ChatCapture::GetChatName(i));
					UI::TableSetColumnIndex(1);
					UI::PushStyleColor(UI::Col::Text, vec4(0.62f, 0.62f, 0.62f, S_OriginalTextOpacity));
					if (g_italicFont !is null) UI::PushFont(g_italicFont);
					UI::TextWrapped(ChatCapture::GetChatText(i));
					if (g_italicFont !is null) UI::PopFont();
					UI::PopStyleColor();
					string translated = Translation::GetTranslationFor(ChatCapture::GetChatName(i), ChatCapture::GetChatText(i));
					if (translated.Length > 0) {
						UI::PushStyleColor(UI::Col::Text, vec4(1.0f, 1.0f, 1.0f, 1.0f));
						UI::TextWrapped(translated);
						UI::PopStyleColor();
					}
				}
				UI::EndTable();
			}
			UI::PopStyleVar();
			UI::PopStyleColor(2);
			if (followBottom) UI::SetScrollHereY(1.0f);
			}
			UI::EndChild();
		}
		UI::End();
		UI::PopStyleVar();
		UI::PopStyleColor();
	}
}
