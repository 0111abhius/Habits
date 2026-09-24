import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CalendarStrip extends StatefulWidget {
  final DateTime selectedDate;
  final Function(DateTime) onDateSelected;
  final Set<String> completedDates; // yyyy-MM-dd

  const CalendarStrip({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    this.completedDates = const {},
  });

  @override
  State<CalendarStrip> createState() => _CalendarStripState();
}

class _CalendarStripState extends State<CalendarStrip> {
  late ScrollController _scrollController;
  late List<DateTime> dates;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    final today = DateTime.now();
    // Generate dates: past 7, today, next 7 (total 15)
    dates = List.generate(15, (i) {
      return today.subtract(Duration(days: 7 - i)); // i=7 => today
    });

    // Scroll to today's date when the widget is first built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final todayIndex = dates.indexWhere((date) =>
          date.year == today.year &&
          date.month == today.month &&
          date.day == today.day);
      if (todayIndex != -1) {
        _scrollController.animateTo(
          todayIndex * 68.0, // 60 (width) + 8 (margin)
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();

    return Container(
      height: 110,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        itemCount: dates.length,
        itemBuilder: (context, index) {
          final date = dates[index];
          final isSelected = date.year == widget.selectedDate.year &&
              date.month == widget.selectedDate.month &&
              date.day == widget.selectedDate.day;
          final isToday = date.year == today.year &&
              date.month == today.month &&
              date.day == today.day;

          final dateKey = DateFormat('yyyy-MM-dd').format(date);
          final isLogged = widget.completedDates.contains(dateKey);

          return GestureDetector(
            onTap: () => widget.onDateSelected(date),
            child: Stack(
              alignment: Alignment.topRight,
              children:[
                Container(
                  width: 60,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : isToday
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('E').format(date),
                          style: TextStyle(
                            color: isSelected
                                ? Theme.of(context).colorScheme.onPrimary
                                : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('d').format(date),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? Theme.of(context).colorScheme.onPrimary
                                : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('MMM').format(date),
                          style: TextStyle(
                            color: isSelected
                                ? Theme.of(context).colorScheme.onPrimary
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if(isLogged)
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Icon(Icons.check_circle, size:12, color: isSelected? Theme.of(context).colorScheme.onPrimary: Theme.of(context).colorScheme.primary),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
} 