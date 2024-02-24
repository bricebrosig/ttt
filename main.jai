// main.jai
//
// a big tic tac toe game

/* todo:
    [x] detect winner of a sub game
    [ ] draw line for winner
    [ ] grey out
    [ ] disable input into complete subgames
    [x] don't draw outside the boundary of the game board
    [ ] switch to drawing around a center point
    [ ] switch to left handed?
    [ ] restart game
    [ ] main menu
    [ ] AI
    [ ] readme with pretty pictures

    [ ] another level of the recursion?

  6 | 7 | 8
  --+---+--
  3 | 4 | 5
  --+---+--
  0 | 1 | 2

  win conditions
  0 == 1 == 2
  0 == 3 == 6

  0 == 4 == 8
  3 == 4 == 5
  1 == 4 == 7
  2 == 4 == 6
  
  6 == 7 == 8
  2 == 5 == 8
*/

my_window: Window_Type;
window_width : s32 = 1080;
window_height: s32 = 1080;

current_time : float64;
last_time    : float64;

L := 6.0;  // big line width
l := 4.0;  // little line width

Letter :: enum {
    NONE;
    X;
    O;
}

WinLineType :: enum {
    C1; C2; C3;
    R1; R2; R3;
    FORWARD;
    BACKWARD;
}

GameState :: struct {
    turn   :      Letter;         // who's turn it is
    board  : [81] Letter;
    wins   : [9]  Letter;
    winner :      Letter;
}

BG_COLOR   := Vector4.{.1, .1, .1, 1};
BASE_COLOR := Vector4.{.8, .8, .8,  1};
HOT_COLOR  := Vector4.{.38, .54, .59, .8};
WIN_COLOR  := Vector4.{.8, .8, .8, .5}

main :: () {
    #if OS == .WINDOWS {
        Windows :: #import "Windows";
        Windows.SetProcessDPIAware();

        // Windows is very bad at thread-switching by default unless you do this. Sad.
        Windows.timeBeginPeriod(1);
    }

    my_window = create_window(window_width, window_height, "Tic-Tac-Toe");
    #if OS == .WINDOWS {
        // @Feature: Add user-specific typelist support.
        Windows.DragAcceptFiles(my_window, cast(Windows.BOOL) true);
    } else #if OS == .LINUX {
        X11 :: #import "X11";
        typelist := string.["url/url", "text/uri-list", "text/plain", "application/octet-stream"];
        X11.enable_drag_and_drop(my_window, typelist);
    } else #if OS == .MACOS {
        #import "Objective_C";
        #import "Objective_C/AppKit";
        types := NSArray(NSPasteboardType).arrayWithObject(NSPasteboardTypeFileURL);
        NSView.registerForDraggedTypes(my_window, types);
    }

    Simp.set_render_target(my_window);

    init_fonts();

    state: GameState;
    state.turn = .X;

    quit := false;
    while !quit {
        current_time = get_time();
        dt := cast(float)(current_time - last_time);
        Clamp(*dt, 0, 0.1);
        last_time = current_time;

        // window events
        Input.update_window_events();
        for Input.get_window_resizes() {
            Simp.update_window(it.window);

            if it.window == my_window {
                should_reinit := (it.width != window_width) || (it.height != window_height);

                window_width  = it.width;
                window_height = it.height;

                if should_reinit  init_fonts();  // Resize the font for the new window size.
            }
        }

        clicked := false;
        
        // other events
        for event: Input.events_this_frame {
            if event.type == .QUIT then quit = true;
            if event.key_code == .MOUSE_BUTTON_LEFT && event.key_pressed {
                clicked = true;
            }
        }

        // click on board
        if clicked {
            mouse_x, mouse_y, _ := get_mouse_pointer_position(true);
            r := get_main_rect(my_window);
            clicked_idx := screen_coord_to_board_idx(mouse_x, mouse_y, r);
            
            print("%\n", clicked_idx);
            
            if clicked_idx < 81 {
                state.board[clicked_idx] = state.turn;
                // state.turn = ifx state.turn == .X then .O else .X;
            }
        }

        // check for winners
        for 0..8 {
            if state.wins[it] == .NONE {
                // if we don't have a winner, check if we do
                state.wins[it] = check_for_winner(state.board, it * 9);
            }
        }

        // check for game over
        state.winner = check_for_winner(state.wins, 0);

        if state.winner != .NONE  print("winner: %", state.winner);

        // draw call
        draw_one_frame(state, dt);

        // reset
        reset_temporary_storage();
    }  // while true
}  // main

draw_one_frame :: (state: GameState, dt: float) {
    Simp.clear_render_target(BG_COLOR.x, BG_COLOR.y, BG_COLOR.z, BG_COLOR.w);
    Simp.set_shader_for_color(true);  // with blend so alpha works

    r := get_main_rect(my_window);

    draw_grid(r, L, color);

    sv := cast(float) r.w / 3;  // vertical step size
    sh := cast(float) r.h / 3;  // horizontal step size

    mouse_x, mouse_y, _ := get_mouse_pointer_position(true);
    main_grid_col, sub_grid_col: int;
    main_grid_row, sub_grid_row: int;

    // draw the 9 subgrids -- since this is right-handed, we draw bottom left to top right
    for i: 0..2 {
        for j: 0..2 {
            // draw the sub grid
            x  := r.x + i * sh;
            y  := r.y + j * sv;
            sr := get_rect(x, y, sh, sv);
            sr = shrink_by(sr, .05);
            draw_grid(sr, l, color);
        }
    }

    // draw hot rect inside that sub grid
    if is_point_in_rect(xx mouse_x, xx mouse_y, r) {
        main_grid_col = cast(int) (mouse_x - r.x) / cast(int) sv;
        main_grid_row = cast(int) (mouse_y - r.y) / cast(int) sh;
        hL := L / 2;
        
        mouse_rect := get_rect(r.x + main_grid_col * sh + hL, r.y + main_grid_row * sv + hL, sh - L, sv - L);
        mouse_rect = shrink_by(mouse_rect, .05);
        
        if is_point_in_rect(xx mouse_x, xx mouse_y, mouse_rect) {
            ssh := (mouse_rect.w / 3);
            ssv := (mouse_rect.h / 3);
            sub_grid_col = cast(int) (mouse_x - mouse_rect.x) / cast(int) ssh;
            sub_grid_row = cast(int) (mouse_y - mouse_rect.y) / cast(int) ssv;

            xhl := ifx sub_grid_col == 0 then 0 else l / 2;
            yhl := ifx sub_grid_row == 0 then 0 else l / 2;

            hot_rect := get_rect(mouse_rect.x + sub_grid_col * ssh + xhl, mouse_rect.y + sub_grid_row * ssv + yhl, ssh - l, ssv - l);
            hot_rect = shrink_by(hot_rect, .05);
            Simp.immediate_quad(hot_rect.x, hot_rect.y, hot_rect.x + hot_rect.w, hot_rect.y + hot_rect.h, hot_color);
        } else {
            sub_grid_col = -1;
            sub_grid_row = -1;
        }
    }

    // draw the Xs and Os
    for letter, i : state.board {
        sub :int = i / 9;  // which sub board we are in
        sub_x, sub_y := idx_to_grid_coord(sub);
        sub_r := grid_coord_to_rect(sub_x, sub_y, r, L);

        ssx, ssy := idx_to_grid_coord(i);
        ssr := grid_coord_to_rect(ssx, ssy, sub_r, l);
        tx, ty := center_of(ssr);

        if letter == .X {
            draw_centered_text(my_font, "X", xx tx, xx ty, color);
        } else if letter == .O {
            draw_centered_text(my_font, "O", xx tx, xx ty, color);
        }
    }

    Simp.draw_text(my_font, 32, 32, tprint("%", state.turn));

    Simp.swap_buffers(my_window);
}  // draw_one_frame

//
// draw a tic tac toe grid inside the given rect
draw_grid :: (r: Rect, l: float, c: Vector4) {
    s := cast(float) r.w / 3;  // the step size of the lines
    hl := l / 2;
    x := r.x;
    y := r.y;
    Simp.immediate_quad(    x + s - hl, y,     x + s + hl, y + r.h, c);
    Simp.immediate_quad(x + 2 * s - hl, y, x + 2 * s + hl, y + r.h, c);
    
    Simp.immediate_quad(x,     y + s - hl, x + r.w,     y + s + hl, c);
    Simp.immediate_quad(x, y + 2 * s - hl, x + r.w, y + 2 * s + hl, c);
}

//
// get the x, y position of the bottom left corner given an index 
// and the rect containing the whole board
idx_to_board_position :: (idx: int, r: Rect, l: float) -> x: float, y: float {
    i := idx % 9;
    s := r.w / 3;
    x := r.x + (i % 3) * (s + l);
    y := r.y + (i / 3) * (s + l);

    return x, y;
}

same :: (a: Letter, b: Letter, c: Letter) -> bool {
    return a == b && b == c && a == c;
}

// TODO (brice): return the line that we should draw as a part of the return information
check_for_winner :: (arr: []Letter, o: int) -> Letter {
    assert(o % 9 == 0);
    for 0..2 {
        i := it * 3 + o;
        if same(arr[i], arr[i + 1], arr[i + 2])  return arr[i];
        
        i = it;
        if same(arr[i], arr[i + 3], arr[i + 6])  return arr[i];
    }

    if same(arr[o], arr[o + 4], arr[o + 8])      return arr[o];
    if same(arr[o + 2], arr[o + 4], arr[o + 6])  return arr[o + 2];

    return .NONE;
}

// reset_state :: (state: *State) {

// }

grid_coord_to_rect :: (xi: int, yi: int, r: Rect, l: float) -> Rect {
    sw  := r.w / 3;
    sh  := r.h / 3;
    xhl := ifx xi == 0 then 0 else l / 2;
    yhl := ifx yi == 0 then 0 else l / 2;
    
    inner_rect := get_rect(r.x + xi * sw + xhl, r.y + yi * sh + yhl, sw - l, sh - l);
    inner_rect = shrink_by(inner_rect, .05);

    return inner_rect;
}

// check if given x, y point is inside of a rect
// @right-handed
is_point_in_rect :: (x: float, y: float, r: Rect) -> bool {
    check_x := x >= r.x && x <= (r.x + r.w);
    check_y := y >= r.y && y <= (r.y + r.h);
    return check_x && check_y;
}

draw_centered_text :: (font: *Simp.Dynamic_Font, text: string, x: int, y: int, color: Vector4) {
    width   := Simp.prepare_text(font, text);
    shift_x := x - (width / 2);
    shift_y := y - font.character_height / 4;
    Simp.draw_prepared_text(font, shift_x, shift_y, color);
}

idx_to_grid_coord :: (idx: int) -> int, int {
    i := idx % 9;
    return i % 3, i / 3;
}

shrink_by :: (r: Rect, p: float) -> Rect {
    nr := shrink(r,  r.w * p);
    nr  = shrink(nr, r.h * p);
    return nr;
}

center_of :: (r: Rect) -> float, float {
    return r.x + r.w / 2, r.y + r.h / 2;
}

screen_coord_to_board_idx :: (x: int, y: int, r: Rect) -> int {
    sw := r.w / 3;
    sh := r.h / 3;
    grid_x := cast(int) (x - r.x) / cast(int) sw;
    grid_y := cast(int) (y - r.x) / cast(int) sh;

    offset := 9 * (grid_x + grid_y * 3);
    hL := L / 2;

    pr := get_rect(r.x + grid_x * sh + hL, r.y + grid_y * sw + hL, sh - L, sw - L);
    pr  = shrink_by(pr, .05);

    ssh := (pr.w / 3);
    ssv := (pr.h / 3);
    sub_grid_col := cast(int) (x - pr.x) / cast(int) ssh;
    sub_grid_row := cast(int) (y - pr.y) / cast(int) ssv;

    return offset + (sub_grid_col + 3 * sub_grid_row);
}

get_main_rect :: (win: Window_Type) -> Rect {
    win_x, win_y, win_w, win_h := get_dimensions(my_window, false);
    s := min(win_w, win_h);

    r := get_rect(cast(float) win_w / 2 - cast(float) s / 2, cast(float) win_h / 2 - cast(float) s / 2, xx s, xx s);
    r = shrink_by(r, .05);

    return r;
}

init_fonts :: () {
    if !working_directory_set {
        // So that we can load our font, set to path of running executable.
        path := path_strip_filename(get_path_of_running_executable());
        set_working_directory(path);

        working_directory_set = true;
    }

    pixel_height := window_height / 22;
    my_font = Simp.get_font_at_size("data", "HeavyDataNerdFont-Regular.ttf", pixel_height);
    assert(my_font != null);
    
    pixel_height /= 2;
    button_font = Simp.get_font_at_size("data", "HeavyDataNerdFont-Regular.ttf", pixel_height);
    assert(button_font != null);

    pixel_height = window_height / 7;
    title_font = Simp.get_font_at_size("data", "HeavyDataNerdFont-Regular.ttf", pixel_height);
}

Font :: Simp.Dynamic_Font;

my_font:     *Font;
button_font: *Font;
title_font:  *Font;


working_directory_set := false;

Simp  :: #import "Simp";
Input :: #import "Input";

#import "Window_Creation";
#import "GetRect";

#import "Basic";
Basic :: #import "Basic"; // :CompilerBug  We need this to resolve to_lower for some reason?!
#import "Math";
#import "System";  // For get_path_of_running_executable. @Cleanup.
#import "String";  // For path_strip_filename. @Cleanup.

modify_string :: (ps: *string, new_value: string) {
    free(ps.*);
    ps.* = copy_string(new_value);
}