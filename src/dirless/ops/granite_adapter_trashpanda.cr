require "granite/adapter/base"
require "trash-panda-db"

class Granite::Adapter::Trashpanda < Granite::Adapter::Base
  QUOTING_CHAR = '"'

  module Schema
    TYPES = {
      "AUTO_Int32" => "INTEGER NOT NULL",
      "AUTO_Int64" => "INTEGER NOT NULL",
      "AUTO_UUID"  => "CHAR(36)",
      "UUID"       => "CHAR(36)",
      "Int32"      => "INTEGER",
      "Int64"      => "INTEGER",
      "created_at" => "VARCHAR",
      "updated_at" => "VARCHAR",
    }
  end

  def clear(table_name : String)
    statement = "DELETE FROM #{quote(table_name)}"
    elapsed_time = Time.measure { open(&.exec(statement)) }
    log statement, elapsed_time
  end

  def insert(table_name : String, fields, params, lastval) : Int64
    statement = String.build do |stmt|
      stmt << "INSERT INTO #{quote(table_name)} ("
      stmt << fields.map { |name| quote(name) }.join(", ")
      stmt << ") VALUES ("
      stmt << fields.map { "?" }.join(", ")
      stmt << ")"
    end

    last_id = -1_i64
    elapsed_time = Time.measure do
      open do |database|
        database.exec statement, args: params
        last_id = database.scalar(last_val).as(Int64) if lastval
      end
    end
    log statement, elapsed_time, params
    last_id
  end

  def import(table_name : String, primary_name : String, auto : Bool, fields, model_array, **options)
    params = [] of Granite::Columns::Type

    statement = String.build do |stmt|
      stmt << "INSERT "
      if options["update_on_duplicate"]?
        stmt << "OR REPLACE "
      elsif options["ignore_on_duplicate"]?
        stmt << "OR IGNORE "
      end
      stmt << "INTO #{quote(table_name)} ("
      stmt << fields.map { |field| quote(field) }.join(", ")
      stmt << ") VALUES "

      model_array.each do |model|
        next unless model.valid?
        model.set_timestamps
        stmt << '('
        stmt << Array.new(fields.size, '?').join(',')
        params.concat fields.map { |field| model.read_attribute field }
        stmt << "),"
      end
    end.chomp(',')

    elapsed_time = Time.measure { open(&.exec(statement, args: params)) }
    log statement, elapsed_time, params
  end

  def update(table_name : String, primary_name : String, fields, params)
    statement = String.build do |stmt|
      stmt << "UPDATE #{quote(table_name)} SET "
      stmt << fields.map { |name| "#{quote(name)}=?" }.join(", ")
      stmt << " WHERE #{quote(primary_name)}=?"
    end
    elapsed_time = Time.measure { open(&.exec(statement, args: params)) }
    log statement, elapsed_time, params
  end

  def delete(table_name : String, primary_name : String, value)
    statement = "DELETE FROM #{quote(table_name)} WHERE #{quote(primary_name)}=?"
    elapsed_time = Time.measure { open(&.exec(statement, value)) }
    log statement, elapsed_time, value
  end

  private def last_val
    "SELECT LAST_INSERT_ROWID()"
  end
end
