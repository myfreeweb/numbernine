#include <gtkmm.h>
#include "gtk-lsh/manager.hpp"
#include "gtk-lsh/multimonitor.hpp"
#include "gtk-lsh/surface.hpp"

class wallpaper {
	Glib::RefPtr<Gio::Settings> settings;

 public:
	std::shared_ptr<Gtk::Window> window;
	Gtk::Image image;
	std::optional<lsh::surface> layer_surface;

	wallpaper(lsh::manager& lsh_mgr, GdkMonitor* monitor) {
		settings = Gio::Settings::create("technology.unrelenting.numbernine.wallpaper",
		                                 "/technology/unrelenting/numbernine/wallpaper/");
		window = std::make_shared<Gtk::Window>(Gtk::WINDOW_TOPLEVEL);
		window->set_default_size(640, 480);
		window->set_decorated(false);
		layer_surface.emplace(lsh_mgr, window, monitor, lsh::layer::background);
		layer_surface->set_anchor(lsh::anchor::top | lsh::anchor::left | lsh::anchor::bottom |
		                          lsh::anchor::right);
		layer_surface->set_size(640, 480);
		settings->bind("picture-path", &image, "file");
		window->add(image);
		window->show_all();
	}

	std::shared_ptr<Gtk::Window> get_window() const { return window; };

	~wallpaper() = default;

	wallpaper(wallpaper&&) = delete;
};

int main(int argc, char* argv[]) {
	auto app = Gtk::Application::create(argc, argv, "technology.unrelenting.numbernine.wallpaper");
	lsh::manager lsh_mgr(app);
	lsh::multimonitor<wallpaper, lsh::manager&> mm(lsh_mgr);
	app->hold();
	app->run();
}