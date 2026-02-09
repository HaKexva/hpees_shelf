# frozen_string_literal: true

# 人員（學生／管理員）標籤規則：與書籍共用 tag_rule_groups / tag_rule_options，依 target = "user" 篩選。
class User
  module TagRules
    class << self
      def groups
        list = TagRuleGroup.where(target: "user").order(:position).includes(:tag_rule_options).to_a
        return _groups_from_db(list) if list.any?
        []
      end

      def all_tag_names_in_groups
        groups.flat_map { |g| (g["options"] || []).map { |o| o["tag_name"].to_s } }.uniq
      end

      def required?(group_index)
        g = groups[group_index]
        g && g["required"]
      end

      def single_select?(group_index)
        g = groups[group_index]
        g.nil? ? true : g["single_select"]
      end

      def optional?(group_index)
        !required?(group_index)
      end

      # 表單內聯的提示文字；空白視為無，有此文字時才顯示下方選單/輸入框
      def option_popup_prompt(group_index, tag_name)
        opt = option_for(group_index, tag_name)
        return "" unless opt
        opt["popup_prompt"].to_s.strip.presence || ""
      end

      def option_source(group_index, tag_name)
        opt = option_for(group_index, tag_name)
        return nil unless opt
        v = (opt["option_source"] || opt[:option_source]).to_s.strip.presence
        %w[manual admins users batch_years].include?(v) ? v : nil
      end

      def option_for(group_index, tag_name)
        g = groups[group_index]
        return nil unless g
        (g["options"] || []).find { |o| o["tag_name"].to_s == tag_name.to_s }
      end

      private

      def _groups_from_db(list)
        list.map do |grp|
          {
            "label" => grp.label.to_s,
            "required" => grp.required,
            "single_select" => grp.single_select,
            "options" => grp.tag_rule_options.map do |opt|
              h = { "tag_name" => opt.tag_name.to_s, "popup_prompt" => opt.popup_prompt.to_s }
              h["option_source"] = opt.option_source.to_s if TagRuleOption.column_names.include?("option_source")
              h
            end
          }
        end.deep_dup
      end
    end
  end
end
