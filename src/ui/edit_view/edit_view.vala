
[GtkTemplate (ui = "/com/toolstack/Folio/edit_view.ui")]
public class Folio.EditView : Gtk.Box {

	public bool toolbar_enabled { get; set; }

	public bool is_editable { get; set; }

	public int scale { get; set; default = 100; }

	public bool text_mode { set { markdown_view.text_mode = value; } }

	public const int MIN_SCALE = 10;
	public const int MAX_SCALE = 600;

	public Gdk.RGBA theme_color {
		get { return markdown_view.theme_color; }
		set {
			markdown_view.theme_color = value;
		}
	}

	public Gtk.TextBuffer buffer {
		get { return markdown_view.buffer; }
		set {
			markdown_view.buffer = value;
			Gtk.TextIter start;
			markdown_view.buffer.get_start_iter (out start);
			markdown_view.buffer.place_cursor (start);
		}
	}

	[GtkChild] public unowned Toolbar toolbar;
	[GtkChild] unowned GtkMarkdown.View markdown_view;
	[GtkChild] public unowned Gtk.ScrolledWindow scrolled_window;

	private Adw.ToastOverlay toast_overlay = null;

	private Gtk.CssProvider note_font_provider = new Gtk.CssProvider ();
	private Gtk.CssProvider font_scale_provider = new Gtk.CssProvider ();

	private bool is_ctrl = false;

	construct {
		var settings = new Settings (Config.APP_ID);

		set_note_font (settings.get_string ("note-font"));
 		set_max_width (settings.get_int ("note-max-width"));
		markdown_view.set_show_line_numbers (settings.get_boolean ("show-line-numbers"));

		markdown_view.notify["text-mode"].connect (update_toolbar_visibility);

		markdown_view.notify["buffer"].connect (() => markdown_view.buffer.notify["cursor-position"].connect (() => {
			var ins = markdown_view.buffer.get_insert ();
			Gtk.TextIter cur;
			markdown_view.buffer.get_iter_at_mark (out cur, ins);
			toolbar.heading_i = (int) markdown_view.get_title_level (cur.get_line ());
		}));
		toolbar.heading_i_changed.connect ((i) => {
			var ins = markdown_view.buffer.get_insert ();
			Gtk.TextIter cur;
			markdown_view.buffer.get_iter_at_mark (out cur, ins);
			markdown_view.set_title_level (cur.get_line (), i);
		});

		Gtk.GestureClick click_controller;
		click_controller = new Gtk.GestureClick () {
			button = Gdk.BUTTON_PRIMARY
		};

		click_controller.released.connect ((n, x, y) => {
			if (is_ctrl) {
				var ins = markdown_view.buffer.get_insert ();
				Gtk.TextIter cur;
				markdown_view.buffer.get_iter_at_mark (out cur, ins);
				var text_tag_url = markdown_view.buffer.tag_table.lookup ("markdown-link");

				if (cur.has_tag (text_tag_url)) {
					Gtk.TextIter start_url, end_url;
					string url_text = "";
					if (!markdown_view.check_if_in_link (markdown_view, out url_text)) {
						start_url = cur;
						end_url = cur;
						start_url.backward_to_tag_toggle (text_tag_url);
						end_url.forward_to_tag_toggle (text_tag_url);

						url_text = markdown_view.buffer.get_slice (start_url, end_url, true);
						url_text = url_text.chomp ().chug ();
					}

					// Check to see if we have an e-mail link to open.
					// check_if_email_link will validate a real url for us.
					if (markdown_view.check_if_email_link (url_text)) {
						if (!url_text.contains ("://"))
							url_text = "mailto:" + url_text;

						try {
							GLib.AppInfo.launch_default_for_uri (url_text, null);
						} catch (Error e) {
							toast (Strings.COULDNT_FIND_APP_TO_HANDLE_URIS);
						}
					} else if ( ( url_text.substring (0,2) == "./" ) ||
						( url_text.substring (0, 3) == "../" ) ||
						( url_text.down ().substring (0, 9) == "file://./" ) ||
						( url_text.down ().substring (0, 10) == "file://../" )
						) {
						if (url_text.down ().substring (0, 7) == "file://" ) {
							url_text = url_text.substring (7, -1);
						}
						var window = (Folio.Window)get_ancestor (typeof (Folio.Window));
						var app = (Folio.Application)window.get_application ();
						var window_model = app.window_model;
						// Is this a link to another note in the current notebook?
						if ( ( url_text[0] == '.' && url_text[1] == '/' ) ) {
							url_text = window_model.notebook.name + url_text.substring (1, -1);
						}
						// Is this a link to another note in another notebook?
						if ( ( url_text[0] == '.' && url_text[1] == '.' && url_text[2] == '/' ) ) {
							url_text = url_text.substring (3, -1);
						}
						// Trim off the .md extension if it exists.
						if (url_text.substring (-3, -1) == ".md") {
							url_text = url_text.substring (0, url_text.length - 3);
						}
						// Try and get the note object.
						var note = window_model.try_get_note_from_path (url_text);
						if (note != null)
							window_model.open_note_in_notebook (note);
						else
							toast ("Failed to find note!");
					}
					else {
						// Since it wasn't an e-mail address, check to see if we have a valid url
						// to open.  check_if_bare_link will validate a real url for us.
						if (markdown_view.check_if_bare_link (url_text)) {
							// If it's bare, add in http by default.
							if (!url_text.contains ("://"))
								url_text = "http://" + url_text;
							try {
								GLib.AppInfo.launch_default_for_uri (url_text, null);
							} catch (Error e) {
								toast (Strings.COULDNT_FIND_APP_TO_HANDLE_URIS);
							}
						} else {
							toast (Strings.COULDNT_FIND_APP_TO_HANDLE_URIS);
						}
					}
				}
			}
		});

		markdown_view.add_controller (click_controller);

		scrolled_window.get_vscrollbar ().margin_top = 48;

		settings.bind ("toolbar-enabled", this, "toolbar-enabled", SettingsBindFlags.DEFAULT);
		settings.bind ("note-font-monospace", markdown_view, "font-monospace", SettingsBindFlags.DEFAULT);
		settings.changed["note-font"].connect(() => set_note_font (settings.get_string ("note-font")));
		settings.changed["note-max-width"].connect(() => set_max_width (settings.get_int ("note-max-width")));

		var window_state = new Settings (@"$(Config.APP_ID).WindowState");
		window_state.bind ("text-scale", this, "scale", SettingsBindFlags.DEFAULT);

		notify["toolbar-enabled"].connect (update_toolbar_visibility);
		notify["is-editable"].connect (() => {
			update_toolbar_visibility ();
			markdown_view.sensitive = is_editable;
		});
		update_toolbar_visibility ();

		notify["scale"].connect(set_font_scale);

		var key_controller = new Gtk.EventControllerKey ();
		key_controller.key_pressed.connect ((keyval, keycode, state) => {
			if (keyval == Gdk.Key.Control_L || keyval == Gdk.Key.Control_R)
				is_ctrl = true;
			return false;
		});
		key_controller.key_released.connect ((keyval, keycode, state) => {
			if (keyval == Gdk.Key.Control_L || keyval == Gdk.Key.Control_R || (state & Gdk.ModifierType.CONTROL_MASK) != 0)
				is_ctrl = false;
		});
		var scroll_controller = new Gtk.EventControllerScroll (Gtk.EventControllerScrollFlags.DISCRETE | Gtk.EventControllerScrollFlags.VERTICAL);
		scroll_controller.scroll.connect ((dx, dy) => {
			if (is_ctrl) {
				if (dy < 0)
					zoom_in ();
				else zoom_out ();
				return true;
			}
			return false;
		});
		add_controller (key_controller);
		markdown_view.add_controller (scroll_controller);
	}

	public void resize_toolbar () {
		toolbar.resize_toolbar ();
	}

	private void toast (string text) {
		if (toast_overlay == null) {
			toast_overlay = (Adw.ToastOverlay)get_ancestor (typeof (Adw.ToastOverlay));
		}
		var toast = new Adw.Toast (text);
		toast_overlay.add_toast (toast);
	}

	public void zoom_in () {
		var new_scale = scale + 10;
		if (new_scale <= MAX_SCALE)
			scale = new_scale;
	}

	public void zoom_out () {
		var new_scale = scale - 10;
		if (new_scale >= MIN_SCALE)
			scale = new_scale;
	}

	public void on_dark_changed (bool dark) {
		markdown_view.dark = dark;
	}

	public void set_line_numbers () {
		var settings = new Settings (Config.APP_ID);
		markdown_view.set_show_line_numbers (settings.get_boolean ("show-line-numbers"));
	}

	private void format_selection (string affix, string second_affix) {
		var buffer = markdown_view.buffer;

		buffer.begin_user_action ();

		if ( !markdown_view.remove_formatting (markdown_view, affix) &&
			 !markdown_view.remove_formatting (markdown_view, second_affix))
			{
			Gtk.TextIter selection_start, selection_end, cursor;
			Gtk.TextMark cursor_mark, selection_start_mark, selection_end_mark;
			buffer.get_selection_bounds (out selection_start, out selection_end);
			buffer.get_iter_at_mark (out cursor, buffer.get_insert ());
			cursor_mark = buffer.create_mark (null, cursor, true);
			selection_start_mark = buffer.create_mark (null, selection_start, true);
			selection_end_mark = buffer.create_mark (null, selection_end, true);

			var is_selected = true;

			if (selection_start.equal (selection_end)) {
				is_selected = false;

				find_word_selection (ref selection_start, ref selection_end);

				buffer.select_range (selection_start, selection_end);
				selection_start_mark = buffer.create_mark (null, selection_start, true);
				selection_end_mark = buffer.create_mark (null, selection_end, true);
			}

			buffer.insert (ref selection_start, affix, affix.length);

			buffer.get_selection_bounds (out selection_start, out selection_end);
			buffer.insert (ref selection_end, affix, affix.length);

			buffer.get_iter_at_mark (out selection_start, selection_start_mark);
			buffer.get_iter_at_mark (out cursor, cursor_mark);

			if (cursor.equal (selection_start)) {
				cursor.forward_chars (affix.length);
			}

			buffer.place_cursor (cursor);

			if (is_selected) {
				buffer.get_iter_at_mark (out selection_start, selection_start_mark);
				buffer.get_iter_at_mark (out selection_end, selection_end_mark);
				selection_end.forward_chars (affix.length);
				buffer.select_range (selection_start, selection_end);
			} else {
				buffer.select_range (cursor, cursor);
			}

			markdown_view.grab_focus ();
		}

		buffer.end_user_action ();
	}

	public void format_selection_bold () {
		format_selection("**", "__");
	}

	public void format_selection_italic () {
		format_selection("_", "*");
	}

	public void format_selection_strikethrough () {
		format_selection("~~", "~");
	}

	public void format_selection_highlight () {
		format_selection("==", "");
	}

	public void insert_link () {
		var buffer = markdown_view.buffer;
		buffer.begin_user_action ();

		if (!markdown_view.check_if_in_link (markdown_view)) {
			var url_found = false;
			Gtk.TextIter selection_start, selection_end;
			buffer.get_selection_bounds (out selection_start, out selection_end);

			if (selection_start.equal (selection_end)) {
				find_word_selection (ref selection_start, ref selection_end);

				buffer.select_range (selection_start, selection_end);
			}

			buffer.get_selection_bounds (out selection_start, out selection_end);
			var selection_text = buffer.get_slice (selection_start, selection_end, true);
			url_found = markdown_view.check_if_bare_link (selection_text);

			Gtk.TextMark start_mark, end_mark;
			buffer.get_selection_bounds (out selection_start, out selection_end);
			// Make sure our marks in in ascending order to simplify things later.
			if (selection_start.compare (selection_end) > 1) {
				start_mark = buffer.create_mark (null, selection_end, true);
				end_mark = buffer.create_mark (null, selection_start, true);
			} else {
				start_mark = buffer.create_mark (null, selection_start, true);
				end_mark = buffer.create_mark (null, selection_end, true);
			}

			{
				buffer.get_iter_at_mark (out selection_start, start_mark);
				if (url_found) {
					buffer.insert (ref selection_start, "[](", 3);
				} else {
					buffer.insert (ref selection_start, "[", 1);
				}
			}
			{
				buffer.get_iter_at_mark (out selection_end, end_mark);
				if (url_found) {
					buffer.insert (ref selection_end, ")", 1);
				} else {
					buffer.insert (ref selection_end, "]()", 3);
				}
			}
			buffer.get_iter_at_mark (out selection_start, start_mark);
			buffer.get_iter_at_mark (out selection_end, end_mark);
			if (url_found) {
				selection_start.forward_char ();
				buffer.place_cursor (selection_start);
			} else {
				selection_end.forward_chars (2);
				buffer.place_cursor (selection_end);
			}
		}

		markdown_view.grab_focus ();
		buffer.end_user_action ();
	}

	public void insert_code_span () {
		format_selection("`", "");
	}

	public void insert_horizontal_rule () {
		var buffer = markdown_view.buffer;

		buffer.begin_user_action ();

		var mark = buffer.get_selection_bound ();
		Gtk.TextIter iter, current_line_start, current_line_end;
		buffer.get_iter_at_mark (out iter, mark);
		current_line_start = iter.copy ();
		current_line_start.backward_line ();
		current_line_start.forward_char ();
		current_line_end = iter.copy ();
		current_line_end.forward_line ();
		current_line_end.backward_char ();

		string current_line = buffer.get_slice (current_line_start, current_line_end, true);

		if (current_line != "- - -") {
			current_line_start.backward_char ();
			current_line_start.forward_line ();
			buffer.insert (ref current_line_start, "- - -\n", 6);
			buffer.get_iter_at_mark (out iter, mark);
			buffer.place_cursor (iter);
		}

		markdown_view.grab_focus ();

		buffer.end_user_action ();
	}

	public void set_font_scale () {
		font_scale_provider.load_from_string (@"textview{font-size:$(scale / 100f)em;}");
		markdown_view.get_style_context ().add_provider (font_scale_provider, -1);
	}

	private void set_note_font (string font) {
		var font_desc = Pango.FontDescription.from_string (font);
		var font_family = font_desc.get_family ();
		var font_weight = (int)font_desc.get_weight ();
		var font_size = font_desc.get_size ();
		var font_units = "pt";
		if (!font_desc.get_size_is_absolute ()) {
			font_size = font_size / Pango.SCALE;
		}
		if (font_size < 4) { font_size = 10; }
		note_font_provider.load_from_string (@"textview{font-family:'$font_family';font-weight:$font_weight;font-size:$font_size$font_units;}");
		markdown_view.get_style_context ().add_provider (note_font_provider, -1);
	}

	private void set_max_width (int w) {
		markdown_view.width_request = w;
		markdown_view.halign = w == -1 ? Gtk.Align.FILL : Gtk.Align.CENTER;
	}

	private void update_toolbar_visibility () {
		toolbar.visible = is_editable && toolbar_enabled && !markdown_view.text_mode;
		resize_toolbar ();
	}

	private void find_word_selection (ref Gtk.TextIter selection_start, ref Gtk.TextIter selection_end) {
		var current_char = selection_start.get_char ();
		// If we're at the end of line, move back one.
		if( current_char == '\n') {
			selection_start.backward_char ();
			current_char = selection_start.get_char ();
		}
		// If the cursor is in a blank spot (1 or more spaces/tabs) then go backwards until
		// we find a word/start of line/start of buffer.
		while ((current_char == ' ' || current_char == '\t') && current_char != '\n' && !selection_start.is_start()) {
			selection_start.backward_char ();
			current_char = selection_start.get_char ();
		}
		// Now continue going backwards until we find the start of the word of end condition.
		while (current_char != '\n' && current_char != ' ' && current_char != '\t' && !selection_start.is_start()){
			selection_start.backward_char ();
			current_char = selection_start.get_char ();
		}
		// Since we are now on the end condition, move forward one character as long as
		// we're not at the very begining of the buffer.
		if (!selection_start.is_start()) {
			selection_start.forward_char();
		}
		current_char = selection_end.get_char ();
		// If we're at the end of line, we're done.
		if( current_char != '\n') {
			while (current_char != '\n' && current_char != ' ' && current_char != '\t' && !selection_end.is_end ()) {
				selection_end.forward_char();
				current_char = selection_end.get_char ();
			}
		}
	}

	public void reset_scroll_position () {
		Gtk.TextIter start;
		markdown_view.buffer.get_start_iter (out start);
		markdown_view.buffer.place_cursor (start);
		scrolled_window.vadjustment.value = 0;
		markdown_view.grab_focus ();
	}
}
