/**
 * TimezoneDetector — pushes the browser's UTC offset (in minutes) to the
 * LiveView server on mount so all date/timestamp displays and filters use
 * the user's actual local timezone.
 *
 * Attach to <body> in root.html.heex so every page gets it.
 */
const TimezoneDetector = {
  mounted() {
    const offset = -new Date().getTimezoneOffset()
    this.pushEvent("tz:offset", { offset_minutes: offset })
  },
}

export default TimezoneDetector
