# frozen_string_literal: true

module Settings
  class TagsController < ApplicationController
    def index
      @tags = ActsAsTaggableOn::Tag.order(:name)
      @tag_rule_groups = TagRuleGroup.order(:position).includes(:tag_rule_options).to_a
      @groups = _all_groups_for_form
      tag_names_in_rules = @groups.flat_map { |g| (g["options"] || []).map { |o| o["tag_name"].to_s.strip }.reject(&:blank?) }.uniq.sort
      tag_records_by_name = ActsAsTaggableOn::Tag.where(name: tag_names_in_rules).index_by(&:name)
      @tag_stats = tag_names_in_rules.map { |name| rec = tag_records_by_name[name]; { name: name, count: rec&.taggings_count.to_i, tag_id: rec&.id } }
    end

    def create
      name = params[:name].to_s.strip
      if name.blank?
        redirect_to settings_tags_path, alert: "請輸入標籤名稱。", status: :unprocessable_entity
        return
      end
      if ActsAsTaggableOn::Tag.exists?(name: name)
        redirect_to settings_tags_path, alert: "標籤「#{name}」已存在。", status: :unprocessable_entity
        return
      end
      ActsAsTaggableOn::Tag.create!(name: name)
      redirect_to settings_tags_path, notice: "已新增標籤「#{name}」。", status: :see_other
    end

    def destroy
      tag = ActsAsTaggableOn::Tag.find_by(id: params[:id])
      if tag
        name = tag.name
        tag.destroy
        redirect_to settings_tags_path, notice: "已刪除標籤「#{name}」。", status: :see_other
      else
        redirect_to settings_tags_path, alert: "找不到該標籤。", status: :see_other
      end
    end

    def update_rules
      groups_array = _build_groups_from_params
      tag_names_in_rules = groups_array.flat_map { |g| (g["options"] || []).map { |o| o["tag_name"].to_s.strip }.reject(&:blank?) }.uniq
      groups_array.each do |g|
        (g["options"] || []).each do |o|
          name = o["tag_name"].to_s.strip
          ActsAsTaggableOn::Tag.find_or_create_by!(name: name) if name.present?
        end
      end
      Book::TagRules.save_groups(groups_array)
      # 刪除已不在規則中且無任何書籍使用的標籤
      ActsAsTaggableOn::Tag.where.not(name: tag_names_in_rules).where(taggings_count: 0).destroy_all
      if params[:auto_save].present?
        head :no_content
      else
        redirect_to settings_tags_path, notice: "標籤規則已更新。", status: :see_other
      end
    end

    def add_group
      pos = TagRuleGroup.maximum(:position).to_i + 1
      TagRuleGroup.create!(label: "新組別", required: false, single_select: true, position: pos)
      redirect_to settings_tags_path, notice: "已新增組別。", status: :see_other
    end

    def add_option
      group = TagRuleGroup.find_by(id: params[:group_id])
      unless group
        redirect_to settings_tags_path, alert: "無此組別。", status: :see_other
        return
      end
      opos = group.tag_rule_options.maximum(:position).to_i + 1
      group.tag_rule_options.create!(tag_name: "", popup_prompt: "", position: opos)
      redirect_to settings_tags_path, notice: "已新增選項。", status: :see_other
    end

    def delete_group
      group = TagRuleGroup.find_by(id: params[:group_id])
      unless group
        redirect_to settings_tags_path, alert: "無此組別。", status: :see_other
        return
      end
      group.destroy
      _reorder_positions
      redirect_to settings_tags_path, notice: "已刪除組別。", status: :see_other
    end

    def delete_option
      group = TagRuleGroup.find_by(id: params[:group_id])
      unless group
        redirect_to settings_tags_path, alert: "無此組別或選項。", status: :see_other
        return
      end
      oi = params[:option_index].to_i
      opt = group.tag_rule_options.order(:position).offset(oi).first
      unless opt
        redirect_to settings_tags_path, alert: "無此選項。", status: :see_other
        return
      end
      opt.destroy
      _reorder_option_positions(group)
      redirect_to settings_tags_path, notice: "已刪除選項。", status: :see_other
    end

    private

    def _all_groups_for_form
      @tag_rule_groups.map do |grp|
        {
          "label" => grp.label.to_s,
          "required" => grp.required,
          "single_select" => grp.single_select,
          "target" => grp.respond_to?(:target) && grp.target.present? ? grp.target.to_s : "book",
          "options" => grp.tag_rule_options.map do |opt|
            h = { "tag_name" => opt.tag_name.to_s, "popup_prompt" => opt.popup_prompt.to_s }
            h["relocation_behavior"] = opt.relocation_behavior.to_s if TagRuleOption.column_names.include?("relocation_behavior")
            h["option_source"] = opt.option_source.to_s if TagRuleOption.column_names.include?("option_source")
            h
          end
        }
      end
    end

    def _build_groups_from_params
      return [] unless params[:groups].is_a?(ActionController::Parameters) || params[:groups].is_a?(Hash)
      raw = params[:groups].respond_to?(:to_unsafe_h) ? params[:groups].to_unsafe_h : params[:groups].to_h
      raw.sort_by { |k, _| k.to_s.to_i }.map do |_k, g|
        opts = g["options"] || g[:options]
        opts = opts.to_unsafe_h if opts.respond_to?(:to_unsafe_h)
        opts = opts.is_a?(Hash) ? opts.sort_by { |ok, _| ok.to_s.to_i }.map { |_, ov| ov } : []
        {
          "label" => (g["label"] || g[:label]).to_s.strip.presence || "未命名",
          "required" => (g["required"] || g[:required]).to_s == "1",
          "single_select" => (g["single_select"] || g[:single_select]).to_s != "0",
          "target" => (g["target"].to_s.strip.presence == "user") ? "user" : "book",
          "options" => opts.map do |o|
            h = {
              "tag_name" => (o["tag_name"] || o[:tag_name]).to_s.strip,
              "popup_prompt" => (o["popup_prompt"] || o[:popup_prompt]).to_s.strip,
              "relocation_behavior" => (o["relocation_behavior"] || o[:relocation_behavior]).to_s.strip.presence
            }
            h["option_source"] = (o["option_source"] || o[:option_source]).to_s.strip.presence if TagRuleOption.column_names.include?("option_source")
            h
          end
        }
      end
    end

    def _reorder_positions
      TagRuleGroup.order(:position).each_with_index { |g, i| g.update_column(:position, i) }
    end

    def _reorder_option_positions(group)
      group.tag_rule_options.reload.order(:position).each_with_index { |o, i| o.update_column(:position, i) }
    end
  end
end
