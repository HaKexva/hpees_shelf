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
      required_alert = view_context.respond_to?(:required_fields_alert) ? view_context.required_fields_alert : nil
      return if flash.blank? && required_alert.blank?
      div(class: "mb-4 space-y-2") do
        if flash[:alert].present?
          div(class: "py-2 px-3 bg-red-50 text-red-600 font-medium rounded-md border border-red-200", role: "alert") { flash[:alert] }
        end
        if required_alert.present?
          div(class: "py-2 px-3 bg-red-50 text-red-600 font-medium rounded-md border border-red-200", role: "alert") { required_alert }
        end
        if flash[:notice].present?
          notice_class = "py-2 px-3 bg-green-50 text-green-600 font-medium rounded-md border border-green-200"
          if auto_dismiss_borrow_success_flash?
            div(
              class: notice_class,
              role: "status",
              data: { controller: "flash-auto-dismiss", flash_auto_dismiss_delay_value: 3000 }
            ) { flash[:notice] }
          else
            div(class: notice_class, role: "status") { flash[:notice] }
          end
        end
      end
    end

    def flash
      view_context.flash
    end

    # Borrow/return home: hide green success after a few seconds (rapid scanning); alerts unchanged.
    def auto_dismiss_borrow_success_flash?
      c = view_context.controller
      (c.controller_name == "public_borrow_return" && c.action_name == "index") ||
        (c.controller_name == "dashboard" && c.action_name == "index")
    end

    def render_desktop_sidebar
      # "hidden lg:flex" so iPad (portrait/split) uses sheet; desktop sidebar from 1024px up
      # 更窄的寬度，保留導覽文字又不吃太多空間
      div(class: "hidden lg:flex w-48 shrink-0 flex-col border-r bg-card h-full") do
        div(class: "p-6") do
          h1(class: "text-lg font-semibold") { APP_NAME }
        end
        div(class: "flex-1 px-4 space-y-2") do
          render_nav_links
        end
        render_sidebar_footer if view_context.current_user
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

          # Fixed width so sidebar is same on every page; tuned narrower to roughly match desktop sidebar width
          SheetContent(side: :right, class: "w-[14rem] max-w-[85vw] flex flex-col") do
            SheetHeader do
              SheetTitle { "導覽選單" }
            end
            div(class: "mt-4 flex-1 flex flex-col gap-2") do
              render_nav_links
            end
            render_sidebar_footer if view_context.current_user
          end
        end
      end
    end

    # Shared navigation links to avoid duplication
    def render_nav_links
      href = view_context.current_user ? view_context.admin_dashboard_path : root_path
      nav_link(href: href) { "借還書" }
      if view_context.current_user
        nav_link(href: books_path) { "書籍管理" }
        nav_link(href: batch_years_path) { "屆數管理" }
        nav_link(href: users_path) { "人員管理" }
      end
    end

    def nav_link(href:, &block)
      active = view_context.current_page?(href)
      link_class = "block px-4 py-2 rounded-md text-sm font-medium transition-colors "
      link_class += active ? "bg-accent text-accent-foreground" : "hover:bg-accent hover:text-accent-foreground"
      a(href: href, class: link_class) do
        block.call
      end
    end

    def render_sidebar_footer
      div(class: "px-4 py-4 border-t") do
        div(class: "text-xs text-muted-foreground truncate mb-2") do
          plain view_context.current_user.name
        end
        render_switch_school_year_button
        render_rollback_school_year_button
        form(action: view_context.logout_path, method: "post") do
          input(type: "hidden", name: "_method", value: "delete")
          input(type: "hidden", name: "authenticity_token", value: view_context.form_authenticity_token)
          button(
            type: "submit",
            class: "w-full inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors " \
                   "px-4 py-2 h-9 border border-input bg-background shadow-sm " \
                   "hover:bg-accent hover:text-accent-foreground"
          ) { "登出" }
        end
      end
    end

    def render_switch_school_year_button
      return unless view_context.current_user_admin?
      return unless BatchYear.show_advance_school_year_button?

      next_roc = BatchYear.display_current_school_year_roc + 1
      form(action: view_context.reassign_grades_batch_years_path, method: "post", class: "mb-2") do
        input(type: "hidden", name: "authenticity_token", value: view_context.form_authenticity_token)
        button(
          type: "submit",
          class: "w-full inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors " \
                 "px-4 py-2 h-9 border border-input bg-background shadow-sm " \
                 "hover:bg-accent hover:text-accent-foreground",
          data: { turbo_confirm: "將開啟指定屆數頁面；學年度會在您送出「儲存屆數指定」後才更新。確定？" }
        ) { "切換至#{next_roc}學年度" }
      end
    end

    def render_rollback_school_year_button
      return unless view_context.current_user_admin?
      return unless BatchYear.can_rollback_school_year?

      prev_roc = BatchYear.display_current_school_year_roc - 1
      form(action: view_context.rollback_school_year_batch_years_path, method: "post", class: "mb-2") do
        input(type: "hidden", name: "authenticity_token", value: view_context.form_authenticity_token)
        button(
          type: "submit",
          class: "w-full inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors " \
                 "px-4 py-2 h-9 border border-input bg-background shadow-sm " \
                 "hover:bg-accent hover:text-accent-foreground",
          data: { turbo_confirm: "將退回至#{prev_roc}學年度，並刪除屆數編號最大的一屆、重算年級。確定？" }
        ) { "返回前一學年度" }
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
