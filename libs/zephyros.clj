(require '[clojure.data.json :as json])
(import '[java.net Socket]
        '[java.util.concurrent ArrayBlockingQueue]
        '[java.io PrintWriter InputStreamReader BufferedReader])

(def chans (ref {}))

(defmacro safely-do-in-background [& body]
  `(future
     (try
       ~@body
       (catch Exception e#
         (.printStackTrace e#)))))

(defn conn-handler [conn]
  ;; (println "ready.")
  (while (nil? (:exit @conn))
    (let [msg-size (Integer/parseInt (.readLine (:in @conn)))
          _ (println "waiting for" msg-size "bytes")
          i (atom 0)
          msg (take msg-size (repeatedly #(do
                                            (println "waiting for byte #" (swap! i inc))
                                            (.read (:in @conn)))))
          msg-str (apply str (map char msg))
          json (json/read-str msg-str)
          ;; _ (println "GOT" json)
          msg-id (json 0)
          chan (get @chans msg-id)]
      (.put chan json))))

(defn connect [server]
  (let [socket (Socket. (:name server) (:port server))
        in (BufferedReader. (InputStreamReader. (.getInputStream socket) "UTF-8"))
        out (PrintWriter. (.getOutputStream socket))
        conn (ref {:in in :out out :socket socket})]
    [(safely-do-in-background (conn-handler conn))
     conn]))

(defn write [conn msg]
  (doto (:out @conn)
    (.print msg)
    (.flush)))

(def zephyros-server {:name "localhost" :port 1235})
(def max-msg-id (atom 0))
(let [[listener tmp-conn] (connect zephyros-server)]
  (def conn tmp-conn)
  (def listen-for-callbacks listener))

(defn send-msg [args]
  (let [msg-id (swap! max-msg-id inc)
        json-str (json/write-str (concat [msg-id] args))
        ;; _ (println "SENDING" json-str)
        json-str-size (count json-str)
        chan (ArrayBlockingQueue. 10)]
    (dosync
     (alter chans assoc msg-id chan))
    (write conn (format "%s\n%s", json-str-size, json-str))
    {:kill #(dosync (alter chans dissoc msg-id))
     :get #(second (.take chan))}))

(defn get-one-value [& args]
  (let [resp (send-msg args)
        val ((:get resp))]
    ((:kill resp))
    val))

(defn do-callback-once [f & args]
  (safely-do-in-background
   (let [resp (send-msg args)
         num-times ((:get resp))
         val ((:get resp))]
     ((:kill resp))
     (f val))))

(defn do-callback-indefinitely [f & args]
  (safely-do-in-background
   (let [resp (send-msg args)]
     ((:get resp))
     (doseq [val (repeatedly (:get resp))]
       (f val)))))








(defn keywordize [m]
  (into {} (for [[k v] m]
             [(keyword k) v])))


;; top level

(defn bind "" [key mods f] (do-callback-indefinitely (fn [_] (f)) 0 "bind" key mods))
(defn listen "" [event f] (do-callback-indefinitely #(f %) 0 "listen" event))

(defn get-focused-window "" [] (get-one-value 0 "focused_window"))
(defn get-visible-windows "" [] (get-one-value 0 "visible_windows"))
(defn get-all-windows "" [] (get-one-value 0 "all_windows"))

(defn get-main-screen "" [] (get-one-value 0 "main_screen"))
(defn get-all-screens "" [] (get-one-value 0 "all_screens"))

(defn get-running-apps "" [] (get-one-value 0 "running_apps"))

(defn alert "" [msg duration] (get-one-value 0 "alert" msg duration))
(defn log "" [msg] (get-one-value 0 "log" msg))
(defn choose-from "" [list title f] (do-callback-once f 0 "choose_from" list title 20 10))

(defn relaunch-config "" [] (get-one-value 0 "relaunch_config"))
(defn get-clipboard-contents "" [] (get-one-value 0 "clipboard_contents"))


;; window

(defn get-window-title "" [window] (get-one-value window "title"))

(defn get-frame "Takes {:x, :y, :w, :h}" [window] (keywordize (get-one-value window "frame")))
(defn get-size "Takes {:w, :h}" [window] (keywordize (get-one-value window "size")))
(defn get-top-left "Takes {:w, :h}" [window] (keywordize (get-one-value window "top_left")))

(defn set-frame "Returns {:x, :y, :w, :h}" [window f] (get-one-value window "set_frame" f))
(defn set-size "Returns {:w, :h}" [window s] (get-one-value window "set_size" s))
(defn set-top-left "Returns {:x, :y}" [window tl] (get-one-value window "set_top_left" tl))

(defn minimize "" [window] (get-one-value window "minimize"))
(defn maximize "" [window] (get-one-value window "maximize"))
(defn un-minimize "" [window] (get-one-value window "un_minimize"))

(defn get-app-for-window "" [window] (get-one-value window "app"))
(defn get-screen-for-window "" [window] (get-one-value window "screen"))

(defn focus-window "" [window] (get-one-value window "focus_window"))
(defn focus-window-left "" [window] (get-one-value window "focus_window_left"))
(defn focus-window-right "" [window] (get-one-value window "focus_window_right"))
(defn focus-window-up "" [window] (get-one-value window "focus_window_up"))
(defn focus-window-down "" [window] (get-one-value window "focus_window_down"))

(defn normal-window? "" [window] (get-one-value window "normal_window?"))
(defn minimized? "" [window] (get-one-value window "minimized?"))


;; app

(defn visible-windows-for-app "" [app] (get-one-value app "visible_windows"))
(defn all-windows-for-app "" [app] (get-one-value app "all_windows"))

(defn get-app-title "" [app] (get-one-value app "title"))
(defn app-hidden? "" [app] (get-one-value app "hidden?"))

(defn show-app "" [app] (get-one-value app "show"))
(defn hide-app "" [app] (get-one-value app "hide"))

(defn kill-app "" [app] (get-one-value app "kill"))
(defn kill9-app "" [app] (get-one-value app "kill9"))


;; screen

(defn screen-frame-including-dock-and-menu "" [screen] (keywordize (get-one-value screen "frame_including_dock_and_menu")))
(defn screen-frame-without-dock-or-menu "" [screen] (keywordize (get-one-value screen "frame_without_dock_or_menu")))

(defn next-screen "" [screen] (get-one-value screen "next_screen"))
(defn previous-screen "" [screen] (get-one-value screen "previous_screen"))
