module RubyUI
  class Layout < Base
    include Phlex::Rails::Helpers::Routes

    APP_NAME = "Hpees Shelf"

    def view_template(&block)
      div(class: "flex h-screen w-full overflow-hidden bg-background") do
        # 1. Desktop Sidebar (Hidden on mobile)
        render_desktop_sidebar

        # 2. Main Content Area
        div(class: "flex flex-col flex-1 w-full") do
          # 3. Mobile Header (Hidden on desktop)
          render_mobile_header

          # 4. Page Content (unified width + padding for all pages and flash)
          main(class: "flex-1 overflow-y-auto p-4") do
            div(class: "w-full max-w-6xl mx-auto px-4 sm:px-6 space-y-4") do
              render_flash_messages
              block.call
            end
          end
        end
      end
    end

    private

    def render_flash_messages
      required_alert = helpers.respond_to?(:required_fields_alert) ? helpers.required_fields_alert : nil
      return if flash.blank? && required_alert.blank?
      div(class: "mb-4 space-y-2") do
        if flash[:alert].present?
          div(class: "py-2 px-3 bg-red-50 text-red-600 font-medium rounded-md border border-red-200", role: "alert") { flash[:alert] }
        end
        if required_alert.present?
          div(class: "py-2 px-3 bg-red-50 text-red-600 font-medium rounded-md border border-red-200", role: "alert") { required_alert }
        end
        if flash[:notice].present?
          div(class: "py-2 px-3 bg-green-50 text-green-600 font-medium rounded-md border border-green-200", role: "status") { flash[:notice] }
        end
      end
    end

    def flash
      helpers.flash
    end

    def render_desktop_sidebar
      # "hidden lg:flex" so iPad (portrait/split) uses sheet; desktop sidebar from 1024px up
      div(class: "hidden lg:flex w-64 shrink-0 flex-col border-r bg-card h-full") do
        div(class: "p-6") do
          h1(class: "text-lg font-semibold") { APP_NAME }
        end
        div(class: "px-4 space-y-2") do
          render_nav_links
        end
      end
    end

    def render_mobile_header
      # "lg:hidden" so iPad and phones get hamburger + sheet; hidden from 1024px up
      header(class: "lg:hidden flex items-center justify-between border-b px-4 py-3 bg-card shrink-0") do
        span(class: "font-semibold") { APP_NAME }

        # Mobile "Hamburger" Menu -> Aggregates to top right
        Sheet do
          SheetTrigger do
            Button(variant: :ghost, size: :icon) do
              menu_icon
            end
          end

          # Fixed width so sidebar is same on every page; matches MobileSidebar (18rem)
          SheetContent(side: :right, class: "w-[18rem] max-w-[85vw] flex flex-col") do
            SheetHeader do
              SheetTitle { "導覽選單" }
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
      nav_link(href: root_path) { "借還書" }
      nav_link(href: books_path) { "書籍管理" }
      nav_link(href: batch_years_path) { "屆數管理" }
      nav_link(href: users_path) { "人員管理" }
    end

    def nav_link(href:, &block)
      active = helpers.current_page?(href)
      link_class = "block px-4 py-2 rounded-md text-sm font-medium transition-colors "
      link_class += active ? "bg-accent text-accent-foreground" : "hover:bg-accent hover:text-accent-foreground"
      a(href: href, class: link_class) do
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
