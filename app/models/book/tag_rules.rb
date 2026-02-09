# frozen_string_literal: true

# 標籤規則：組別與選項存於 tag_rule_groups / tag_rule_options，由使用者在「設定 → 標籤」自行設定。
class Book
  module TagRules
    APP_SETTING_GROUPS = "tag_rule_groups"

    class << self
      def groups
        _migrate_from_app_setting_if_needed
        list = TagRuleGroup.where(target: [ nil, "book" ]).order(:position).includes(:tag_rule_options).to_a
        return _groups_from_db(list) if list.any?
        []
      end

      def save_groups(groups_array)
        TagRuleGroup.transaction do
          TagRuleGroup.destroy_all
          groups_array.each_with_index do |g, pos|
            t = (g["target"].to_s.strip.presence == "user") ? "user" : "book"
            group = TagRuleGroup.create!(
              label: (g["label"].to_s.strip.presence || "未命名"),
              required: (g["required"] == true || g["required"].to_s == "1"),
              single_select: (g["single_select"] != false && g["single_select"].to_s != "0"),
              position: pos,
              target: t
            )
            (g["options"] || []).each_with_index do |o, opos|
              attrs = {
                tag_name: (o["tag_name"].to_s.strip),
                popup_prompt: (o["popup_prompt"].to_s.strip),
                position: opos
              }
              attrs[:relocation_behavior] = (o["relocation_behavior"].to_s.strip.presence) if TagRuleOption.column_names.include?("relocation_behavior")
              attrs[:option_source] = (o["option_source"].to_s.strip.presence) if TagRuleOption.column_names.include?("option_source")
              group.tag_rule_options.create!(attrs)
            end
          end
        end
      end

      def all_tag_names_in_groups
        groups.flat_map { |g| (g["options"] || []).map { |o| o["tag_name"].to_s } }.uniq
      end

      def other_tag_names(available_tag_names)
        in_groups = all_tag_names_in_groups
        available_tag_names.reject { |n| in_groups.include?(n.to_s) }
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

      # 內聯選單來源：manual=手動輸入, admins=來自管理員名單, users=來自人員名單, batch_years=來自屆數名單；空=不顯示額外欄位
      def option_source(group_index, tag_name)
        opt = option_for(group_index, tag_name)
        return nil unless opt
        v = (opt["option_source"] || opt[:option_source]).to_s.strip.presence
        %w[manual admins users batch_years].include?(v) ? v : nil
      end

      # 屆數切換時此標籤（書來源）的處理：keep=維持原班級只更新年級, ask=詢問指定屆數, nil=沿用舊邏輯
      def option_relocation_behavior(group_index, tag_name)
        opt = option_for(group_index, tag_name)
        return nil unless opt
        v = opt["relocation_behavior"].to_s.strip.presence
        %w[keep ask none].include?(v) ? v : nil
      end

      def group_for_tag(tag_name)
        groups.each_with_index do |g, i|
          tags = (g["options"] || []).map { |o| o["tag_name"].to_s }
          return i if tags.include?(tag_name.to_s)
          return i if tag_name.to_s.end_with?("老師的書") && tags.include?(Book::TAG_TEACHER_PREFIX)
        end
        nil
      end

      def group_index_by_label(label)
        groups.index { |g| g["label"].to_s == label.to_s }
      end

      def single_select_by_label?(group_label)
        i = group_index_by_label(group_label)
        i.nil? ? true : single_select?(i)
      end

      def optional_by_label?(group_label)
        i = group_index_by_label(group_label)
        i.nil? ? false : optional?(i)
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
              h["relocation_behavior"] = opt.relocation_behavior.to_s if TagRuleOption.column_names.include?("relocation_behavior")
              h["option_source"] = opt.option_source.to_s if TagRuleOption.column_names.include?("option_source")
              h
            end
          }
        end.deep_dup
      end

      def _migrate_from_app_setting_if_needed
        return if TagRuleGroup.any?
        raw = AppSetting.get(APP_SETTING_GROUPS)
        return if raw.blank?
        data = JSON.parse(raw)
        return unless data.is_a?(Array) && data.any?
        save_groups(data)
      rescue JSON::ParserError, TypeError
        nil
      end
    end
  end
end
