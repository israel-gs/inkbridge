package com.inkbridge.data.capture

import com.inkbridge.domain.model.StylusSample

/**
 * Decides which StylusSink calls an Android [android.view.MotionEvent] action
 * should produce. Pure function — unit-testable without Android framework.
 *
 * Background: MotionEventMapper extracts the continuous state (x/y/pressure/tilt)
 * per pointer, but the transition events (DOWN/UP, HOVER_ENTER/EXIT) must be
 * translated into discrete STYLUS_BUTTON and STYLUS_PROXIMITY wire frames.
 * Without them, the macOS server only receives STYLUS_MOVE and never injects
 * a leftMouseDown — cursor moves, no stroke.
 */
object StylusRouter {

    sealed class Action {
        data class Sample(val sample: StylusSample) : Action()
        data class Button(
            val primaryPressed: Boolean,
            val secondaryPressed: Boolean,
            val timestampNs: Long,
        ) : Action()
        data class Proximity(val entering: Boolean, val timestampNs: Long) : Action()
    }

    /**
     * Android MotionEvent action constants we route on.
     * Copied locally so this file has zero Android framework dependency.
     */
    object Actions {
        const val ACTION_DOWN = 0
        const val ACTION_UP = 1
        const val ACTION_MOVE = 2
        const val ACTION_CANCEL = 3
        const val ACTION_HOVER_MOVE = 7
        const val ACTION_HOVER_ENTER = 9
        const val ACTION_HOVER_EXIT = 10
    }

    /**
     * @param actionMasked the `event.actionMasked` value
     * @param samples the samples produced by [MotionEventMapper.map] for this event
     * @param timestampNs monotonic clock in nanoseconds at receive time (for button/proximity frames)
     * @return ordered list of [Action] the ViewModel should dispatch to the [com.inkbridge.domain.model.StylusSink]
     */
    fun route(
        actionMasked: Int,
        samples: List<StylusSample>,
        timestampNs: Long,
    ): List<Action> {
        return when (actionMasked) {
            Actions.ACTION_HOVER_ENTER ->
                listOf(Action.Proximity(entering = true, timestampNs = timestampNs)) +
                    samples.map(Action::Sample)

            Actions.ACTION_HOVER_EXIT ->
                samples.map(Action::Sample) +
                    Action.Proximity(entering = false, timestampNs = timestampNs)

            Actions.ACTION_DOWN ->
                // Sample MUST precede the button so the server learns the touch
                // position + pressure/tilt BEFORE synthesising leftMouseDown.
                // Otherwise the down event fires with no pressure and drawing
                // apps paint a large "max pressure" blob at the stroke start.
                samples.map(Action::Sample) + Action.Button(
                    primaryPressed = true, secondaryPressed = false, timestampNs = timestampNs,
                )

            Actions.ACTION_UP ->
                samples.map(Action::Sample) + Action.Button(
                    primaryPressed = false, secondaryPressed = false, timestampNs = timestampNs,
                )

            Actions.ACTION_CANCEL ->
                // Treat CANCEL like UP — release the button so drawing apps close the stroke.
                samples.map(Action::Sample) + Action.Button(
                    primaryPressed = false, secondaryPressed = false, timestampNs = timestampNs,
                )

            Actions.ACTION_MOVE, Actions.ACTION_HOVER_MOVE ->
                samples.map(Action::Sample)

            else -> samples.map(Action::Sample)
        }
    }
}
