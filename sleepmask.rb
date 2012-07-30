#!/usr/bin/env ruby
# vim:set fileencoding=UTF-8:
# Sleepmask
# A dumb terminal wrapper for RemGlk
# Copyright (c) 2012 Justin de Vesine
# Released under the MIT license - See README.md

require 'rubygems'
require 'yajl'
require 'yajl/json_gem'
require 'eventmachine'
require 'optparse'

STDOUT.sync = true

execpath = File.dirname(File.realdirpath(File.absolute_path(__FILE__)))
$interpreters = {
  :glulxe => File.join(execpath, '..', 'glulxe-047-rem', 'glulxe'),
  :nitfol => File.join(execpath, '..', 'nitfol-0.5-rem', 'remnitfol'),
  :cheapglulxe => File.join(execpath, '..', 'glulxe-047-rem', 'glulxe'),
  :olddebugcheapnitfol => File.join(execpath, '..', 'nitfol-0.5-rem', 'remnitfol') + " -i -no-spell",
  :fizmo => File.join(execpath, '..', 'fizmo-rem', 'fizmo-glktermw', 'fizmo-glktermw'),
  :fizmodev => File.join(execpath, '..', 'fizmo-rem-dev', 'fizmo-glktermw', 'fizmo-glktermw'),
  :debugcheapnitfol => File.join(execpath, '..', 'fizmo-rem', 'fizmo-glktermw', 'fizmo-glktermw'),
  :cheaphe => File.join(execpath, '..', 'hugo-rem', 'glk', 'heglk'),
  :cheaptads => File.join(execpath, '..', 'floyd-tads-rem', 'build', 'linux.release', 'tads', 'tadsr'),
  :debugcheaptads => File.join(execpath, '..', 'floyd-tads-rem', 'build', 'linux.debug', 'tads', 'tadsr')
}

$skipsave = {
  :cheaptads => true,
  :debugcheaptads => true
}
options = {}

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: sleepmask.rb [options] [gamefile]"
  options[:debug] = false
  options[:verbose] = false
  options[:width] = 70
  options[:height] = 24 
  options[:interpreter] = :glulxe

  opts.on('-i', '--interpreter TERP', 'Interpreter') do |terp|
    if $interpreters.has_key? terp.to_sym
      options[:interpreter] = terp.to_sym
    else
      puts "Error: bad interpreter"
      puts "Possible terps are:"
      $interpreters.each do |name, val|
        puts "    #{name}"
      end
      exit
    end
  end

  opts.on('-w', '--width WIDTH', 'Width of "screen"') do |width|
    options[:width] = width.to_i
  end

  opts.on('-r', '--height HEIGHT', 'Height of "screen"') do |height|
    options[:height] = height.to_i
  end

  opts.on('-v', '--verbose', 'Verbose output') do
    options[:verbose] = true
  end

  opts.on('-d', '--debug', 'Debugging output (even more verbose)') do
    options[:debug] = true
  end

  opts.on('-h', '--help', 'Display this screen') do
    puts opts
    exit
  end
end

optparse.parse!

$options = options

$debug = options[:debug]
if options[:debug]
  options[:verbose] = true
end

if ARGV.empty?
  puts "%% No gamefile specified, exiting."
  exit
end

gamefile = ARGV[0]
gamepath = File.expand_path(gamefile)
if !File.exists? gamepath
  puts "%% No gamefile found: #{gamefile}"
  exit
end

def word_wrap(text, line_width = nil)
  width = line_width.nil? ? $options[:width] : line_width
  text.split("\n").collect do |line|
    begin
      # convert nonbreaking spaces to normal spaces
      line.gsub!(/\xc2\xa0/u, ' ') 
    rescue
    end
    line.length > width ? line.gsub(/(.{1,#{width}})(\s+|$)/, "\\1\n").strip : line
  end * "\n"
end

class RemHandler < EM::Connection
  attr_reader :inputqueue
  attr_reader :remqueue

  def initialize(inputq, remq)
    @inputqueue = inputq
    @remqueue = remq
    @gen = nil
    @windows = {}
    @inputs = []

    @queueinput = Proc.new do |data|
      @remqueue.push data
      @inputqueue.pop &@queueinput
    end
    @inputqueue.pop &@queueinput

    @sendinput = Proc.new do |action|
      input_id = nil
      gen = nil
      msgtype = "line"
      msgdetail = nil
      msg = action[:msg]
      if !@inputs.empty?
        @inputs.each do |input|
          if input[:type] == "line"
            input_id = input[:id]
            gen = input[:gen]
            break
          elsif input[:type] == "char"
            msgtype = "char"
            input_id = input[:id]
            gen = input[:gen]
            break
          elsif input[:type] == "fileref_prompt"
            msgtype = "specialresponse"
            msgdetail = input[:type]
            gen = input[:gen]
          end
        end
      end

      if !input_id.nil?
        if msgtype == "char"
          if msg.empty?
            value = "return"
          elsif msg[0] == "/"
            parts = msg.split(' ')
            if parts.count == 1
              value = msg.slice(1)
            else
              value = parts[1]
            end
            if value == "space"
              value = " "
            end
          else
            value = msg[0]
          end
        else
          value = msg
        end
        message = {
          :type => msgtype,
          :gen => gen.to_i,
          :window => input_id.to_i,
          :value => value.to_s
        }

        puts "%% Sending: #{message.to_json}" if $debug
        send_data(message.to_json)
      elsif msgdetail == "fileref_prompt"
        message = {
          :type => msgtype,
          :gen => gen.to_i,
          :response => "fileref_prompt",
          :value => msg.to_s
        }

        puts "%% Sending special response: #{message.to_json}" if $debug
        send_data(message.to_json)
      else
        puts "%% Couldn't send: #{msg}"
      end
      #send_data(msg)
    end

  end

  def post_init
    @parser = Yajl::Parser.new(:symbolize_keys => true)
    @parser.on_parse_complete = method(:object_parsed)
    init = {
      :type => "init",
      :gen => 0,
      :metrics => {
        :width => $options[:width],
        :height => $options[:height]
      }
    }
    send_data(init.to_json)
  end

  def run_to_s(run, opts = {})
    options = {
      :solo => false
    }

    options.update(opts)

    close = false
    line = run[:text]
    sopen = ""
    sclose = ""

    case run[:style]
    when "emphasized"
      run[:style] = "em"
    when "user1"
      run[:style] = "u1"
    when "user2"
      run[:style] = "u2"
    end

    case run[:style]
    when "header"
      if options[:solo]
        sopen = "# "
        sclose = ""
      else
        sopen = "<b>"
        sclose = "</b>"
      end
    when "subheader"
      if options[:solo]
        sopen = "## "
        sclose = ""
      else
        sopen = "<i>"
        sclose = "</i>"
      end
    when "alert"
      if options[:solo]
        sopen = "** "
        sclose = ""
      else
        sopen = "<strong>"
        sopen = "</strong>"
      end
    when "input"
      sopen = "\n> "
      sclose = "\n"
      line = line.upcase
    when "normal"
      sopen = ""
      sclose = ""
    when "preformatted"
      sopen = ""
      sclose = ""
    else
      sopen = "<#{run[:style]}>"
      sclose = "</#{run[:style]}>"
    end

    s = "#{sopen}#{line}#{sclose}"
    #s = word_wrap(run[:text]).split("\n").collect do |l|
      #"#{sopen}#{l}#{sclose}"
    #end * "\n"

    return s
  end

  def object_parsed(obj)
    if obj[:type] == "pass"
      puts "%% Passing." if $debug
      return
    end

    if obj.has_key? :gen
      @gen = obj[:gen]
    end

    if obj[:type] == "error"
      puts "%% Critical error."
      puts "%% Message: #{obj[:message]}"
      return
    end

    if obj[:type] != "update"
      puts "%% Unknown event type: #{obj[:type]}"
      puts obj.inspect
      return
    end

    if obj.has_key? :windows
      obj[:windows].each do |window|
        puts "%% Window: #{window.inspect}" if $debug
        @windows[window[:id]] = window
        if window[:type] == "grid"
          @windows[window[:id]][:grid] = [" " * window[:width]] * window[:height]
        else
          @windows[window[:id]][:buffer] = []
        end
      end
    end

    if obj.has_key?(:inputs) && !obj.has_key?(:specialinput)
      @inputs = obj[:inputs]
      puts "Inputs: #{@inputs.inspect}" if $debug
      @remqueue.pop &@sendinput
    end

    if obj.has_key? :contents
      obj[:contents].each do |content|
        puts "%% Content: #{content.inspect}" if $debug
        window = @windows[content[:id]]
        if window[:type] == "grid"
          content[:lines].each do |line|
            window[:grid][line[:line]] = ""
            line[:content].each do |run| 
              window[:grid][line[:line]] += run_to_s(run)
            end
          end
          puts "%% Grid window #{content[:id]}:" if $options[:verbose]
          puts "] " + window[:grid].join("\n] ")
          puts "%% ---" if $options[:verbose]
        else
          if content.has_key? :clear and content[:clear]
            window[:buffer] = []
            puts "%% clearing window #{content[:id]}" if $options[:verbose]
          end
          if content.has_key? :text and !content[:text].empty?
            content[:text].each do |text|
              s = ""
              if text.has_key? :content and !text[:content].empty?
                if text[:content].length == 1
                  s = run_to_s(text[:content][0], {:solo => true})
                else
                  text[:content].each do |run|
                    s += run_to_s(run)
                  end
                end
              end

              if text.has_key? :append and text[:append]
                window[:buffer] << "" if window[:buffer].last.nil?
                window[:buffer][-1] += s
              else
                window[:buffer] << s
              end
            end
          end
          window[:buffer] = word_wrap(window[:buffer].join("\n")).split("\n")
          puts window[:buffer].join("\n")
          window[:buffer] = [window[:buffer].last]
        end
      end
    end

    if obj.has_key? :specialinput
      @inputs = [obj[:specialinput]]
      @inputs[0][:gen] = @gen
      puts "Special inputs: #{@inputs.inspect}" if $debug
      puts "%% Enter a #{obj[:specialinput][:filetype]} filename to #{obj[:specialinput][:filemode]}:"
      @remqueue.pop &@sendinput
    end

    #ap obj

  end
  def receive_data data
    puts "%% Parser got: #{data}" if $options[:debug]
    @parser << data
  end
  def unbind
    puts "#{$options[:interpreter]} quit with exit status: #{get_status.exitstatus}"
    EM.stop
  end
end


class KeyboardHandler < EM::Connection
  include EM::Protocols::LineText2

  attr_reader :queue

  def initialize(q)
    @queue = q
  end

  def receive_line(data)
    puts "Keyboard got: '#{data}'" if $debug
    if data == "/quit" 
      puts "%% Quitting!"
      EM.stop
    end
    @queue.push({:msg => data})
  end
  def unbind
    EM.stop
  end
end


EM.run{
  inputq = EM::Queue.new
  remq = EM::Queue.new
  puts "#{$interpreters[$options[:interpreter]]}  '#{gamepath}'" if $options[:debug]
  EM.popen("#{$interpreters[$options[:interpreter]]}  '#{gamepath}'", RemHandler, inputq, remq)
  EM.open_keyboard(KeyboardHandler, inputq)
}


