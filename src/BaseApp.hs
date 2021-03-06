module BaseApp where

import Graphics.Gloss.Data.Point
--import Graphics.Gloss.Data.Vector
import Graphics.Gloss.Interface.IO.Game
import Data.List (intercalate)
import Data.Maybe (isJust, fromJust)
--import Debug.Trace
import Text.Read (readMaybe)

import BaseClasses
import Physics

-------------------------- обработчик событий --------------------------
app_handle_events :: Event -> Application -> IO Application
app_handle_events (EventResize ws) app = return app {app_scale = sc}
  where
    (x, y) = ws
    (bx, by) = (base_size app)
    sc = min ((fromIntegral x) / (fromIntegral bx)) ((fromIntegral y) / (fromIntegral by)) -- масштаб
-- костыли для масштаба
app_handle_events (EventMotion (x, y)) app = (foldr (elem_action event) (return app) (elems app))
  where 
    s = (app_scale app)
    event = (EventMotion (x / s, y / s))
app_handle_events (EventKey a b c (x, y)) app = (foldr (elem_action event) (return app) (elems app))
  where 
    s = (app_scale app)
    event = (EventKey a b c (x / s, y / s))

 
elem_action :: Event -> Interface -> IO Application -> IO Application
elem_action event element app = if (is_active element) 
                                then 
                                  do cur_app <- app
                                     (action (ibase element)) event cur_app
                                else app

-- игнорируем скрытость
elem_action_all:: Event -> Interface -> IO Application -> IO Application
elem_action_all event element app = do cur_app <- app
                                       (action (ibase element)) event cur_app

action_none :: Event -> Application -> IO Application
action_none _ app = return app

-- запихнуть несколько действий в одно
action_multi :: [(Event -> Application -> IO Application)] -> Event -> Application -> IO Application
action_multi acts event app = (foldr do_action (return app) (map (\a -> (a event)) acts))
-- кажется, где-то уже была композиция списка функций, но проще написать ещё раз
do_action :: (Application -> IO Application) -> IO Application -> IO Application
do_action func app = do cur_app <- app
                        func cur_app


-- проверка попадания точки в интерфейс
check_pos :: BaseInterface -> Point -> Bool
check_pos base pos = pointInBox pos ld_corner ru_corner
  where
    ld_corner = (place base)
    ru_corner = ld_corner + (size base)

-- клик по элементу интерфейса
action_click :: BaseInterface -> (Event -> Application -> IO Application) -> Event -> Application -> IO Application
action_click base f (EventKey (MouseButton LeftButton) Down m pos) app | check_pos base pos = f event app
                                                                       | otherwise = return app
  where
     event = (EventKey (MouseButton LeftButton) Down m pos)
action_click _ _ _ app = return app


-- клик по кнопке
action_button_click :: Int -> (Application -> IO Application) -> Event -> Application -> IO Application
action_button_click num f _ app = f (replace_int num new_button app)
  where
    old_button = (elems app) !! num
    new_button = old_button {b_time = 0.0}


-- взаимодействие со слайдером
action_slider :: Int -> Event -> Application -> IO Application
action_slider num (EventKey (MouseButton LeftButton) Down _ pos) app | check_pos base pos = set_slider_pos num pos app
                                                                     | otherwise = return app
  where
    base = (ibase ((elems app) !! num))
action_slider num (EventMotion pos) app | (s_m_act ((elems app) !! num)) = set_slider_pos num pos app
action_slider num (EventKey (MouseButton LeftButton) Up _ _) app = return (replace_int num new_sl app)
  where
    new_sl = ((elems app) !! num) {s_m_act = False}
action_slider _ _ app = return app

set_slider_pos :: Int -> Point -> Application -> IO Application
set_slider_pos num pos app = return (replace_int num new_sl app)
  where
    old_sl = ((elems app) !! num)
    new_sl = old_sl {s_curpt = new_curpt, s_m_act = True}
    new_curpt = get_sl_pt old_sl pos

-- вычислить номер деления слайдера по клику
get_sl_pt :: Interface -> Point -> Int
get_sl_pt sl pos = (max 0 (min ((s_pts sl) - 1) (round (x / d_pt))))
  where 
    x = (fst pos) - (fst (place (ibase sl))) - dx
    (sx, _) = (size (ibase sl))
    (dx, _) = (s_indent sl)
    d_pt = (sx - 2 * dx) / ((fromIntegral (s_pts sl)) - 1)


action_load_world :: Application -> IO Application
action_load_world app = load_world (filename ((elems app) !! 0)) app
--                                 do r_world <- load_world h_smooth_ place_ size_ filename
--                                    return (replace_int 0 r_world app)
--                                    where
--                                      world = (elems app) !! 0
--                                      h_smooth_ = (h_smooth world)
--                                      place_ = (place (ibase world))
--                                      size_ = (size (ibase world))

action_save_world :: Application -> IO Application
action_save_world app = do save_world app (filename ((elems app) !! 0))
                           return app

action_clear_world :: Application -> IO Application
action_clear_world app = return (replace_int 0 new_world app)
  where
    new_world = ((elems app) !! 0) {entities = [], is_pause = True}

------------------------------------------------------------------------

-------------------------- отрисовка приложения ------------------------
app_draw :: Application -> IO Picture
app_draw app = return (scale c c (pictures (map elem_draw (elems app))))
  where
    c = (app_scale app)

elem_draw :: Interface -> Picture
elem_draw element | (is_active element) = (draw (ibase element)) $ element
                  | otherwise = Blank

draw_none :: Interface -> Picture
draw_none _ = Blank

draw_button :: Interface -> Picture
draw_button button = translate (x + sx / 2) (y + sy / 2) (pictures [color cur_col (rectangleSolid sx sy),
                                              color (b_col button) (rectangleSolid (sx - 6) (sy - 6)),
                                              color (b_text_col button) (text_ 0.2 (b_text button))])
  where
    (x, y) = (place (ibase button))
    (sx, sy) = (size (ibase button))
    cur_col = if (b_time button) < 0.4 then (b_click_col button) else black

draw_text_field :: Interface -> Picture
draw_text_field tf = translate (x + sx / 2) (y + sy / 2) 
                     (color (t_col tf) (text_ (t_scale tf) (t_text tf)))
  where
    (x, y) = (place (ibase tf))
    (sx, sy) = (size (ibase tf))

draw_slider :: Interface -> Picture
draw_slider sl = translate (x + sx / 2) (y + sy / 2) (pictures [color cur_col (rectangleSolid sx sy),
                                  color (s_col sl) (rectangleSolid (sx - 2 * dx) (sy - 2 * dy)),
                                  color (s_sl_col sl) (translate (-sx / 2 + sl_pos) 0
                                                  (rectangleSolid (s_sl_size sl) (sy - 2 * dy)))])
  where
    (x, y) = (place (ibase sl))
    (sx, sy) = (size (ibase sl))
    (dx, dy) = (s_indent sl)
    sl_pos = dx + (fromIntegral (s_curpt sl)) * d_pt
    d_pt = (sx - 2 * dx) / ((fromIntegral (s_pts sl)) - 1)
    cur_col = black


draw_world :: Interface -> Picture
draw_world world = translate x y (pictures [color (back_col world) (polygon [(0, 0), (0, sy), (sx, sy), (sx, 0)]),
                                           (pictures (map (draw_entity (h_smooth world)) (entities world))),
                                           draw_target world
                                           --, (draw_qtree coords qtree)
                                           ])
  where
    (x, y) = (place (ibase world))
    (sx, sy) = (size (ibase world))
    --coords = ((0, 0), (sx, sy))
    --qtree = foldr (qtr_insert coords (h_smooth world)) (QLeaf []) (entities world)

draw_target :: Interface -> Picture
draw_target world | check_pos (ibase world) (x, y) = translate dx dy (color col (circle r))
                  | otherwise = Blank
  where
    (x, y) = (m_pos world)
    (dx, dy) = (m_pos world) - (place (ibase world))
    r = (edit_radius world)
    act = (action_type world)
    col = if (act /= 1) && (m_act world) then green else red

--------------------- костыль для тестирования -------------------------
draw_qtree :: (Point, Point) -> QuadTree -> Picture
draw_qtree _ (QLeaf []) = Blank
draw_qtree _ (QLeaf p) = pictures (map 
  (\ent -> (color red (translate (fst (e_pos ent)) (snd (e_pos ent)) (circleSolid 2)))) p)
draw_qtree coords (QNode ul ur dl dr) = pictures [color red (Line [(x_m, y_d), (x_m, y_u)]),
                                                  color red (Line [(x_l, y_m), (x_r, y_m)]),
                                                  draw_qtree ((x_l, y_m), (x_m, y_u)) ul,
                                                  draw_qtree ((x_m, y_m), (x_r, y_u)) ur,
                                                  draw_qtree ((x_l, y_d), (x_m, y_m)) dl,
                                                  draw_qtree ((x_m, y_d), (x_r, y_m)) dr]
  where
    ((x_l, y_d), (x_r, y_u)) = coords
    x_m = (x_l + x_r) / 2
    y_m = (y_d + y_u) / 2
------------------------------------------------------------------------


-- x, y = координаты частицы; <четвёртый "_"> r = радиус; c = цвет
draw_entity :: Float -> Entity -> Picture
draw_entity h (Particle (x, y) _ m _ _ c _) = pictures [color c (translate x y (circleSolid (h / 2))),
                                            color (withAlpha (0.05 * m) c) (translate x y (circleSolid h))]
                                          -- color c (translate x y (circleSolid r))
--draw_entity _ = Blank

-- нарисовать текст "приблизительно" по центру с масштабом s
text_ :: Float -> String -> Picture
text_ s txt = translate (-35 * s * fromIntegral (length txt)) (-50 * s) (scale s s (text txt))
------------------------------------------------------------------------

-------------------------- обработчик времени --------------------------
app_process :: Float -> Application -> IO Application
app_process time app = return (app {elems = map (elem_process time) (elems app)})


elem_process :: Float -> Interface -> Interface
elem_process time element | (is_active element) = ((process (ibase element)) $ time) element
                          | otherwise = element

process_none :: Float -> Interface -> Interface
process_none _ element = element


process_time :: Float -> Interface -> Interface
process_time time (Button a b c d e t h) = (Button a b c d e (t + time) h)
process_time _ elem_ = elem_


process_world :: Float -> Interface -> Interface
process_world time world | (not (is_pause world)) = edit_world new_world
                         | otherwise = world
  where
    h = (h_smooth world)
    delta = (min time (1.0 / (fromIntegral const_FPS)))
    dt = (delta * (time_speed world))

    qtree_0 = foldr (qtr_insert coords (h * const_tree_size)) (QLeaf []) (entities world)
    f_vic_0 = (qtr_get_vicinity coords qtree_0 h [])
    --f_vic_0 = (get_vicinity world h)
    tmp_world = world { entities = (map (refresh_density f_vic_0 world) (entities world))}

    qtree_1 = foldr (qtr_insert coords (h * const_tree_size)) (QLeaf []) (entities tmp_world)
    f_vic_1 = (qtr_get_vicinity coords qtree_1 h [])
    --f_vic_1 = (get_vicinity tmp_world h)
    new_world = (tmp_world { entities = (map (process_entity f_vic_1 tmp_world dt) (entities tmp_world))})
    --trace (if test_vic /= test_vic_old then ((show test_vic) ++ " | " ++ (show test_vic_old) ++ "\n") else "")

    coords = ((0, 0), (size (ibase world)))

    --test_vic = sort (map e_id (f_vic_0 (390, 10)))
    --test_vic_old = sort (map e_id (f_vic_0_old (390, 10)))
    --test_len = (length test_vic)
    --test_len_old = (length test_vic_old)

-- взаимодействие пользователя с миром
edit_world :: Interface -> Interface
edit_world world | ((check_pos (ibase world) (m_pos world)) && (m_act world)) = new_world
                 | otherwise = world
  where
    new_world = world {entities = new_entities}
    old_entities = entities world
    r = edit_radius world
    act = (action_type world)
    new_entities | (act == 0) = filter (\ent -> ((dist (e_pos ent) w_pos) > r)) old_entities
                 | otherwise = old_entities
   -- new_particle = Particle {e_pos = w_pos,
   --                          e_speed = (0, 0), -- (mulSV (-0.5 * 0.0001) (2 * w_pos - w_size)),
   --                          e_mass = 1,
   --                          e_dense = 1.0, -- само пусть считается
   --                          e_radius = 20,
   --                          e_color = makeColor 0.0 0.0 0.6 1.0,
   --                          e_id = length (entities world)}
    w_place = (place (ibase world))
   -- w_size = (size (ibase world))
    w_pos = (m_pos world) - w_place -- положение указателя относительно мира
    --wx = (fst (size (ibase world))) / 2
    --wy = (snd (size (ibase world))) / 2


refresh_density :: (Point -> [Entity]) -> Interface -> Entity -> Entity
refresh_density f_vic world ent = ent {e_dense = density world {entities = vicinity} pos}
  where
    -- покойся с миром, идиотский баг: "r = (e_radius ent)"
    pos = (e_pos ent)
    vicinity = f_vic pos
            -- (get_vicinity r pos world)

process_entity :: (Point -> [Entity]) -> Interface -> Float -> Entity -> Entity
process_entity f_vic world time (Particle (x, y) (vx, vy) m p r c i) = Particle new_pos new_vel m p r c i
-- что-то может пойти не так, если world не (World ...), а другой интерфейс (Button/Slider)
  where
    (f_x, f_y) = use_force p (vx, vy) world {entities = vicinity} (x, y)  -- и здесь был r вместо h
    tmp_vx = vx + time * (f_x / m)
    tmp_vy = vy + time * (f_y / m) - const_g * time  -- добавляем ускорение свободного падения
    (new_pos, new_vel) = (bound_bounce ((h_smooth world) / 2) const_r (size (ibase world))
                          ((x + time * (vx + tmp_vx) / 2, y + time * (vy + tmp_vy) / 2), 
                           (tmp_vx, tmp_vy)))
    const_g = (constants world) !! 4
    const_r = (constants world) !! 5
    vicinity = f_vic (x, y)
             --(get_vicinity (h_smooth world) (x, y) world)
-- посчитали силу -> использовали силу -> проехали -> отразились
--process_entity _ _ e = e

------------------------------------------------------------------------

-- получить активные элементы интерфейса

act_elems :: Application -> [Interface]
act_elems app = filter (\a -> (is_active a)) (elems app)

-- изменить один элемент интерфейса
replace_int :: Int -> Interface -> Application -> Application
replace_int n new app = app {elems = (take n el) ++ (new : (drop (n + 1) el))}
                        where el = elems app

------------------------------------------------------------------------

-- загрузка состояния мира их файла, принимает путь к файлу
-- формат файла: описание частицы в отдельной строке
-- '#' - комментарий

--                                 TODO : запихать остальные параметры в файл                

load_world :: String -> Application -> IO Application
load_world file app = 
  do file_text <- (readFile file)
     let strings = (filter (\s -> (s /= []) && ((head (head s)) /= '#')) (map words (lines file_text))) ++ [[]]
     let new_world = ((elems app) !! 0) {
            entities = (map fromJust (filter isJust (zipWith load_particle [1..] (tail (tail strings)))))
          , back_col = black -- load_color_l (head strings)
          , time_speed = 1.0
          , is_pause = True
          , constants = base_consts}
     -- волшебный мегакостыль
     --return (replace_int 0 new_world (load_sliders const_sliders (strings !! 1) app))
     tmp_app <- trigger_sliders color_sliders_mod -- заменить мир сразу, один раз
                (load_sliders color_sliders (strings !! 0) (replace_int 0 new_world app))
     trigger_sliders const_sliders
                (load_sliders const_sliders (strings !! 1) tmp_app)


load_particle :: Int -> [String] -> Maybe Entity
load_particle p_id (x_pos : (y_pos : (x_speed : (y_speed : (mass : (rad : col)))))) = 
  Just Particle { e_pos = ((read x_pos :: Float), (read y_pos :: Float))
                , e_speed = ((read x_speed :: Float), (read y_speed :: Float))
                , e_mass = (read mass :: Float)
                , e_dense = 1.0 -- всё равно пересчитается
                , e_radius = (read rad :: Float)
                , e_color = load_color_l col
                , e_id = p_id}
load_particle _ _ = Nothing
-- получить цвет из первых 4 элементов списка (RGBA)
load_color_l :: [String] -> Color
load_color_l (col_r : (col_g : (col_b : (col_a : _)))) = makeColor (read col_r :: Float) (read col_g :: Float)
                                                                   (read col_b :: Float) (read col_a :: Float)
load_color_l _ = black

load_sliders :: [Int] -> [String] -> Application -> Application
load_sliders slid consts app = if (length vals) == (length slid) then new_app else app
  where
    vals = (map fromJust (filter isJust 
           (map (readMaybe :: String -> Maybe Int) consts)))
    new_app = (foldr set app (zip slid vals))
    set = (\(pos, val) res -> replace_int pos (((elems res) !! pos) {s_curpt = val}) res)


-- -с-п-а-с-е-н-и-е- сохранение мира в файл
save_world :: Application -> String -> IO ()
save_world app file = writeFile file ((write_f_list (get_slider_vals color_sliders app)) ++ "\n" 
                                   ++ (write_f_list (get_slider_vals const_sliders app)) ++ "\n" 
                                   ++ (write_entities (entities world)))
  where
    world = (elems app) !! 0

-- получить список позиций слайдеров с константами симуляции
const_sliders :: [Int]
const_sliders = [14, 16, 18, 20, 22, 24, 26]

-- получить список позиций слайдеров, задающих цвет фона мира
color_sliders :: [Int]
color_sliders = [42, 43, 44]

-- кого пинать
color_sliders_mod :: [Int]
color_sliders_mod = [41]

get_slider_vals :: [Int] -> Application -> [Int]
get_slider_vals sliders app = map s_curpt (get_sliders sliders app)

-- можно получать не только слайдеры...
get_sliders :: [Int] -> Application -> [Interface]
get_sliders sliders app = (foldr get [] sliders)
  where
    get = (\pos res -> ((elems app) !! pos) : res)

-- читерский пинок слайдеров (так сложилось, что мб не только слайдеры, но идейно нужно пинать слайдеры :/)
trigger_sliders :: [Int] -> Application -> IO Application
trigger_sliders int app = (foldr (elem_action_all event) (return app) (get_sliders int app))
  where
    event = (EventMotion (0, 0))
-------------

write_color :: Color -> String
write_color col = drop 5 (show col)

write_f_list :: (Show a) => [a] -> String
write_f_list list = foldr (++) "" (map ((++ " ") . show) list)

write_entities :: [Entity] -> String
write_entities ents = foldl write_next_entity "" ents

-- страшная строчка
write_next_entity :: String -> Entity -> String
write_next_entity buf (Particle (x, y) (vx, vy) m _ r col _) = buf ++ "\n" ++ (intercalate " " (map show [x, y, vx, vy, m, r])) ++ " " ++ (write_color col)
--write_next_entity _ buf = buf
