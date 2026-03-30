# frozen_string_literal: true

module Imports
  # Создаёт лиды из строк таблицы; пишет result_summary и LeadEvent.
  class LeadImportProcessor
    class Error < StandardError; end

    def self.call(lead_import)
      new(lead_import).call
    end

    def initialize(lead_import)
      @import = lead_import
    end

    attr_reader :import

    def call
      raise Error, "Нет файла" unless import.file.attached?

      import.update!(status: "processing", error_message: nil)

      import.file.blob.open do |tmp|
        path = tmp.path
        ext = SpreadsheetReader.extension_for(import.file.filename.to_s)
        headers, row_enum = SpreadsheetReader.each_data_row(path, ext)
        mapping = normalize_mapping(import.column_mapping, headers)

        created = 0
        skipped = 0
        errors = []

        row_enum.each_with_index do |cells, idx|
          row_num = idx + 2
          attrs = row_to_attrs(headers, cells, mapping)
          if skip_row?(attrs)
            skipped += 1
            next
          end

          lead = import.account.leads.build(
            company_name: attrs[:company_name],
            contact_name: attrs[:contact_name],
            email: attrs[:email],
            phone: attrs[:phone],
            stage: attrs[:stage].presence || "new",
            source: "import",
            owner: import.user,
            score: 0
          )
          lead.metadata = (lead.metadata || {}).merge(
            "import" => { "lead_import_id" => import.id, "row" => row_num }
          )

          if lead.save
            created += 1
            lead.lead_events.create!(
              actor: import.user,
              event_type: "lead_imported",
              payload: { "lead_import_id" => import.id, "row" => row_num }
            )
          else
            errors << { "row" => row_num, "message" => lead.errors.full_messages.join(", ") }
          end
        end

        summary = {
          "created" => created,
          "skipped" => skipped,
          "errors" => errors,
          "error_rows" => errors.size
        }
        import.update!(
          status: "completed",
          result_summary: summary,
          error_message: errors.present? ? "Часть строк с ошибками — см. отчёт ниже." : nil
        )
      end
    rescue StandardError => e
      raise if e.is_a?(Error)

      import.update!(status: "failed", error_message: "#{e.class}: #{e.message}")
      Rails.logger.error("[Imports::LeadImportProcessor] #{e.class}: #{e.message}\n#{e.backtrace&.first(8)&.join("\n")}")
    end

    private

    def normalize_mapping(raw, headers)
      h = raw.stringify_keys.slice(*ColumnMapper::FIELD_KEYS)
      out = {}
      h.each do |k, v|
        next if v.blank?

        if headers.include?(v)
          out[k] = v
        else
          match = headers.find { |x| x.to_s.strip.casecmp?(v.to_s.strip) }
          out[k] = match if match
        end
      end
      out
    end

    def row_to_attrs(headers, cells, mapping)
      attrs = { stage: "new" }
      mapping.each do |field, header_name|
        i = headers.index(header_name)
        next unless i

        val = normalize_cell(cells[i])
        next if val.nil?

        case field
        when "company_name"
          attrs[:company_name] = val.to_s.truncate(255)
        when "contact_name"
          attrs[:contact_name] = val.to_s.truncate(255)
        when "email"
          attrs[:email] = val.to_s.truncate(255)
        when "phone"
          attrs[:phone] = val.to_s.truncate(255)
        when "stage"
          attrs[:stage] = normalize_stage(val)
        end
      end
      attrs
    end

    def normalize_cell(val)
      case val
      when nil then nil
      when String then val.strip.presence
      when Numeric then val.to_s.presence
      when Date then val.iso8601
      when Time then val.iso8601
      else val.to_s.strip.presence
      end
    end

    def normalize_stage(val)
      s = val.to_s.downcase.strip
      return "new" if s.blank?

      map = {
        "квалифицирован" => "qualified", "qualified" => "qualified",
        "предложение" => "proposal", "proposal" => "proposal",
        "переговоры" => "negotiation", "negotiation" => "negotiation",
        "выигран" => "won", "won" => "won",
        "проигран" => "lost", "lost" => "lost"
      }
      return map[s] if map[s]

      Lead::STAGES.include?(s) ? s : "new"
    end

    def skip_row?(attrs)
      attrs[:company_name].blank? && attrs[:email].blank?
    end
  end
end
