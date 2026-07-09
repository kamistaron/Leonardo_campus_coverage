# Leonardo Campus Coverage Simulation

This project started years ago when I was commuting to Politecnico di Milano almost every day. There were places on campus where I could barely send a WhatsApp message or upload a file of just a few kilobytes. I kept wondering: *why does coverage suddenly disappear, and what actually determines whether a signal reaches a specific location?*

Years later, I finally built this simulation to satisfy that curiosity. Using **MATLAB's ray tracing and coverage analysis tools**, together with real-world base station data from **OpenCellID**, this project simulates wireless coverage in an urban environment around the Città Studi / Leonardo campus area.

---

## 🛠️ Implementation Details

To balance accuracy with practical processing times, the simulation relies on the following key parameters:

*   **Maximum Range:** Set to **600 meters**. In practice, this depends heavily on the deployment scenario and the radio technology (e.g., 5G small cells typically cover much shorter distances than older macro base stations).
*   **Resolution:** Configured to a **5-meter grid**. On my hardware, this required about 4 minutes to compute the ray tracing and coverage maps. A finer resolution is possible but drastically increases computation time.
*   **Maximum Reflections (`MaxNumReflections`):** Set to **2**. Increasing this value allows rays to undergo more reflections before being discarded, which improves real-world accuracy at the cost of additional CPU time.
*   **Refraction:** This parameter can also be toggled/included to make the propagation model more representative of complex real-world environments.

---

## 📝 Key Observations & Notes

*   **The "No Signal" Threshold:** In the project visualization/video, a designation of "No Signal" simply means that no signal was predicted *at the chosen spatial resolution*. Because each $5 \times 5\text{ m}$ cell is represented by a single averaged value, local micro-variations within that cell are smoothed out. A specific physical point might actually have decent reception, but still show up as poor coverage if its surrounding cell area has a weak signal.
*   **Antenna Offsets:** You may notice that some antennas appear slightly offset from the exact center or edges of rooftops. Their coordinates were pulled directly from the OpenCellID database, meaning slight real-world positioning inaccuracies are inherited.

---

## 💡 Conclusion & Feedback

This project was a fantastic opportunity to deep-dive into radio propagation, ray tracing algorithms, and wireless coverage analysis. 

I would love to hear your thoughts, feedback, or suggestions on how to further optimize or improve the model! Feel free to open an issue or reach out.