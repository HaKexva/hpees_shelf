module RubyUI
  class Layout < Base

    APP_NAME = "Hpees Shelf"
    
    def view_template(&block)
      div(class: "flex h-screen w-full overflow-hidden bg-background") do
        # 1. Desktop Sidebar (Hidden on mobile)
        render_desktop_sidebar

        # 2. Main Content Area
        div(class: "flex flex-col flex-1 w-full") do
          # 3. Mobile Header (Hidden on desktop)
          render_mobile_header

          # 4. Page Content
          main(class: "flex-1 overflow-y-auto p-4") do
            block.call
          end
        end
      end
    end

    private

    def render_desktop_sidebar
      # 'hidden md:flex' ensures this is only visible on desktop
      div(class: "hidden md:flex w-64 flex-col border-r bg-card h-full") do
        div(class: "p-6") do
          h1(class: "text-lg font-semibold") { APP_NAME }
        end
        div(class: "px-4 space-y-2") do
          render_nav_links
        end
      end
    end

    def render_mobile_header
      # 'md:hidden' ensures this is only visible on mobile
      header(class: "md:hidden flex items-center justify-between border-b px-4 py-3 bg-card") do
        span(class: "font-semibold") { APP_NAME }

        # Mobile "Hamburger" Menu -> Aggregates to top right
        Sheet do
          SheetTrigger do
            Button(variant: :ghost, size: :icon) do
              menu_icon
            end
          end
          
          # The Sheet slides in. You can use side: :top, :left, or :right
          SheetContent(side: :right) do
            SheetHeader do
              SheetTitle { "Navigation" }
            end
            div(class: "mt-4 flex flex-col gap-2") do
              render_nav_links
            end
          end
        end
      end
    end

    # Shared navigation links to avoid duplication
    def render_nav_links
      nav_link(href: "#") { "借還書" }
      nav_link(href: "#") { "書籍管理" }
      nav_link(href: "#") { "人員管理" }
    end

    def nav_link(href:, &block)
      a(href: href, class: "block px-4 py-2 rounded-md hover:bg-accent hover:text-accent-foreground text-sm font-medium transition-colors") do
        block.call
      end
    end

    def menu_icon
      svg(
        xmlns: "http://www.w3.org/2000/svg",
        width: "24",
        height: "24",
        viewBox: "0 0 24 24",
        fill: "none",
        stroke: "currentColor",
        stroke_width: "2",
        stroke_linecap: "round",
        stroke_linejoin: "round",
        class: "lucide lucide-menu"
      ) do |s|
        s.path(d: "M4 12h16")
        s.path(d: "M4 6h16")
        s.path(d: "M4 18h16")
      end
    end
  end
end