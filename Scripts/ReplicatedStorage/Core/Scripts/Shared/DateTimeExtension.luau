--!strict
local DateTimeExtension = {}

export type DateTimeTable = {
	Year: number,
	Month: number,
	Day: number,
	Hour: number, 
	Minute: number,
	Second: number,
	Millisecond: number,
}

function DateTimeExtension.GetDataTimeTable(dateTime: DateTime): DateTimeTable
	return dateTime:ToUniversalTime() :: DateTimeTable
end

--获取指定时间的日期
function DateTimeExtension.GetDate(dateTime: DateTime): DateTimeTable
	local date: DateTimeTable = dateTime:ToUniversalTime() :: DateTimeTable
	date.Hour = 0
	date.Minute = 0
	date.Second = 0
	date.Millisecond = 0
	return date
end

--获取现在的日期
function DateTimeExtension.GetNowDate(): DateTimeTable
	return DateTimeExtension.GetDate(DateTime.now())
end

return DateTimeExtension
