void Main() {
	DebugUI::Initialize();
	while (true) {
		if (Translation::HasPending()) {
			Translation::TranslateNext();
		} else {
			sleep(100);
		}
	}
}

void Render() {
	ChatCapture::Poll();
	DebugUI::RenderWindow();
}
