release:
	rake build
	gem push pkg/percy-selenium-*
